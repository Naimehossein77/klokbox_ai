import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:heif_converter/heif_converter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:klokbox_ai/face_recognition.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'box_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Similarity Demo',
      home: ImageSimilarityPage(),
    );
  }
}

class ImageSimilarityPage extends StatefulWidget {
  @override
  _ImageSimilarityPageState createState() => _ImageSimilarityPageState();
}

class _ImageSimilarityPageState extends State<ImageSimilarityPage> {
  Interpreter? _interpreter;
  Interpreter? faceInterpreter;
  final ImagePicker _picker = ImagePicker();
  List<double>? _queryFeature;

  List<SimilarImage> _similarImages = [];
  Map<int, List<SimilarImage>> _faceSimilarImages = {};
  Database? _database;
  int _processed = 0;
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    init(context);
  }

  init(context) async {
    await loadModel(context);
    await initializeDatabase();
  }

  Future<void> loadModel(context) async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/effecientnet.tflite');
      faceInterpreter = await Interpreter.fromAsset('assets/facenet_512.tflite');
      _interpreter!.allocateTensors();
      faceInterpreter!.allocateTensors();
      print('Model loaded successfully');
    } catch (e) {
      print('Error loading model: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading model: $e')),
      );
    }
  }

  Future<void> initializeDatabase() async {
    await deleteDatabase(join(await getDatabasesPath(), 'image_features.db'));
    _database = await openDatabase(
      join(await getDatabasesPath(), 'image_features.db'),
      onCreate: (db, version) {
        db.execute(
          'CREATE TABLE features(id TEXT PRIMARY KEY, path TEXT, feature TEXT)',
        );
        db.execute(
          'CREATE TABLE face_features(id TEXT PRIMARY KEY, path TEXT, feature TEXT)',
        );
      },
      version: 1,
    );
    await loadImagesFromGallery();
  }

  Future<void> loadImagesFromGallery() async {
    final PermissionState permission =
        await PhotoManager.requestPermissionExtend();
    if (permission.isAuth) {
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );

      if (albums.isEmpty) return;

      final recentAlbum = albums[0];
      int page = 0;
      const int pageSize = 50;
      bool hasMore = true;

      while (hasMore && page < 5) {
        List<AssetEntity> media = await recentAlbum.getAssetListPaged(
          page: page,
          size: pageSize,
        );

        if (media.isEmpty) {
          hasMore = false;
          break;
        }

        for (var asset in media) {
          try {
            List<Map<String, dynamic>> existingFeature = await _database!.query(
              'features',
              where: 'id = ?',
              whereArgs: [asset.id],
            );
            if (mounted) {
              setState(() {
                _processed++;
              });
            }
            if (existingFeature.isNotEmpty) {
              continue;
            }
            print('existing feature not found. processing....');

            File? file = await asset.file;

            if (file != null) {
              try {
                Uint8List bytes = await FlutterImageCompress.compressWithFile(
                      file.path,
                      minWidth: 1024,
                      minHeight: 1024,
                      quality: 70,
                      format: CompressFormat.jpeg,
                    ) ??
                    await file.readAsBytes();
                // if (file.path.endsWith('.heic') ||
                //     file.path.endsWith('.HEIC')) {
                //   // Extract the .heic file
                //   final String tempDir = Directory.systemTemp.path;

                //   final String heicFilePath = file.path;
                //   final String extractedFilePath = '$tempDir/temp.png';

                //   // Use a library to convert HEIC to JPEG
                //   // For example, using the heic_to_jpg package
                //   final result = await HeifConverter.convert(heicFilePath,
                //       output: extractedFilePath, format: 'png');
                //   if (result != null) {
                //     bytes = await File(result).readAsBytes();
                //   } else {
                //     continue;
                //   }
                // } else {
                //   bytes = await file.readAsBytes();
                // }
                if (bytes != null) {
                  List<double> feature = await extractFeatureVector(bytes);
                  await storeFeatureInDatabase(asset.id, asset.id, feature);

                  //TODO: This block of code is for face recognition
                  List<Uint8List> faceImages = await cropFaces(bytes);

                  for (int i = 0; i < faceImages.length; i++) {
                    List<double> faceFeature =
                        await extractFaceEmbeddings(faceImages[i]);
                    print(faceFeature);
                    await storeFaceFeatureInDB(
                        '${asset.id}_face_$i', asset.id, faceFeature);
                  }
                }
              } finally {
                if (await file.exists()) {
                  // await file.delete();
                }
              }
            }
          } catch (e) {
            print('Error processing image ${(await asset.file)!.path}: $e');
            continue;
          }
        }

        page++;
      }
    } else {
      print('Permission not granted');
    }
  }

  Future<void> storeFeatureInDatabase(
      String id, String path, List<double> feature) async {
    await _database?.insert(
      'features',
      {'id': id, 'path': path, 'feature': jsonEncode(feature)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> storeFaceFeatureInDB(
      String id, String path, List<double> feature) async {
    await _database?.insert(
      'face_features',
      {'id': id, 'path': path, 'feature': jsonEncode(feature)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Float32List preprocessImage(Uint8List imageData) {
    img.Image? originalImage = img.decodeImage(imageData);
    if (originalImage == null) {
      throw Exception('Could not decode image');
    }
    img.Image resizedImage =
        img.copyResize(originalImage, width: 224, height: 224);
    List<double> imageAsList = [];
    for (int y = 0; y < resizedImage.height; y++) {
      for (int x = 0; x < resizedImage.width; x++) {
        img.Pixel pixel = resizedImage.getPixel(x, y);
        int r = pixel.r.toInt();
        int g = pixel.g.toInt();
        int b = pixel.b.toInt();
        imageAsList.add(r / 255.0);
        imageAsList.add(g / 255.0);
        imageAsList.add(b / 255.0);
      }
    }
    return Float32List.fromList(imageAsList);
  }

  Future<List<double>> extractFeatureVector(Uint8List imageData) async {
    Float32List input = preprocessImage(imageData);
    print(input.buffer.asFloat32List());
    var inputTensor = input.buffer.asFloat32List().reshape([1, 224, 224, 3]);
    var outputBuffer = List.filled(1000, 0.0).reshape([1, 1000]);
    print('inputTensor length: ${inputTensor.length}');
    print('outputBuffer length: ${outputBuffer.length}');
    try {
      _interpreter!.run(inputTensor, outputBuffer);
    } on Exception catch (e) {
      Fluttertoast.showToast(msg: "Error: $e");
    }

    List<double> features = List<double>.from(outputBuffer[0]);
    double maxVal = features.reduce(max);
    double minVal = features.reduce(min);

    if (maxVal != minVal) {
      features = features.map((e) => (e - minVal) / (maxVal - minVal)).toList();
    }

    // return features..addAll(faceFeature);

    return features;
  }

  Future<List<double>> extractFaceEmbeddings(Uint8List imageData) async {
    if (mounted) {
      setState(() {
        _imageBytes = imageData;
      });
    }
    // Preprocess the image for face detection
    Uint8List uint8ListInput = img
        .copyResize(img.decodeImage(imageData)!, width: 160, height: 160)
        .getBytes();
    Float32List input = Float32List.fromList(
        uint8ListInput.map((e) => e.toDouble() / 255.0).toList());
    // print(input.buffer.asFloat32List());
    var inputTensor = input.buffer.asFloat32List().reshape([1, 160, 160, 3]);
    print('face reshape: ${inputTensor}');
    var outputBuffer = List.filled(512, 0.0).reshape([1, 512]);

    // Run the face detection model
    faceInterpreter!.run(inputTensor, outputBuffer);

    // Extract the face embeddings
    List<double> faceEmbeddings = List<double>.from(outputBuffer[0]);

    // Normalize the face embeddings
    double maxVal = faceEmbeddings.reduce(max);
    double minVal = faceEmbeddings.reduce(min);
    if (maxVal != minVal) {
      faceEmbeddings =
          faceEmbeddings.map((e) => (e - minVal) / (maxVal - minVal)).toList();
    }

    return faceEmbeddings;
  }

  Future<void> findSimilarImages() async {
    if (_queryFeature == null) return;
    List<Map<String, dynamic>> maps = await _database!.query('features');
    List<SimilarImage> results = [];
    for (var map in maps) {
      List<double> feature =
          (jsonDecode(map['feature']) as List).cast<double>();
      double similarity = cosineSimilarity(_queryFeature!, feature);
      if (similarity > 0.50) {
        results.add(SimilarImage(path: map['path'], similarity: similarity));
      }
    }
    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    setState(() {
      _similarImages = results.take(10).toList();
    });
  }

  double cosineSimilarity(List<double> vectorA, List<double> vectorB) {
    if (vectorA.length != vectorB.length) {
      throw Exception('Vectors must be of the same length');
    }
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < vectorA.length; i++) {
      dotProduct += vectorA[i] * vectorB[i];
      normA += vectorA[i] * vectorA[i];
      normB += vectorB[i] * vectorB[i];
    }
    double norm = (sqrt(normA) * sqrt(normB));
    if (norm == 0) {
      return 0.0;
    }

    return dotProduct / norm;
  }

  Future<List<SimilarImage>> findSimilarFaceImages(
      List<double> faceFeature) async {
    List<Map<String, dynamic>> maps = await _database!.query('face_features');
    List<SimilarImage> results = [];
    for (var map in maps) {
      List<double> feature =
          (jsonDecode(map['feature']) as List).cast<double>();
      double similarity = cosineSimilarity(faceFeature, feature);
      if (similarity > 0.59) {
        results.add(SimilarImage(path: map['path'], similarity: similarity));
      }
    }
    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    // setState(() {
    //   _similarImages = results.take(10).toList();
    // });
    // return results.toSet().toList();
    final uniqueResults = results.toSet().toList();
    final uniqueById =
        {for (var img in uniqueResults) img.path: img}.values.toList();
    return uniqueById;
  }

  Future<void> pickImage(BuildContext context) async {
    try {
      final XFile? imageFile =
          await _picker.pickImage(source: ImageSource.gallery);
      if (imageFile != null) {
        final file = File(imageFile.path);
        Uint8List bytes;
        Uint8List? compressedBytes =
            await FlutterImageCompress.compressWithFile(
          file.path,
          minWidth: 1024,
          minHeight: 1024,
          quality: 70,
          format: CompressFormat.png,
        );
        bytes = compressedBytes ?? await file.readAsBytes();
        // final String tempDir = Directory.systemTemp.path;

        // final String heicFilePath = file.path;
        // final String extractedFilePath = '$tempDir/temp.png';

        // final result = await HeifConverter.convert(heicFilePath,
        //     output: extractedFilePath, format: 'png');
        // if (result != null) {
        //   bytes = await File(result).readAsBytes();
        // } else {
        //   bytes = await file.readAsBytes();
        // }
        // if (compressedBytes != null) {
        //   bytes = compressedBytes;
        // } else {
        //   bytes = await file.readAsBytes();
        // }
        setState(() {
          _queryFeature = null;
          _faceSimilarImages = {};
          _similarImages = [];
        });
        _queryFeature = await extractFeatureVector(bytes);
        List<Uint8List> faceImages = await cropFaces(bytes);
        for (int i = 0; i < faceImages.length; i++) {
          List<double> faceFeature = await extractFaceEmbeddings(faceImages[i]);
          print(faceFeature);
          _faceSimilarImages[i] = (await findSimilarFaceImages(faceFeature));
        }
        findSimilarImages();
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Image Similarity Demo"),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: Text(
                'Processed $_processed images',
                style: TextStyle(fontSize: 16),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          if (_imageBytes != null)
            Image.memory(
              _imageBytes!,
              height: 200,
              width: 200,
              fit: BoxFit.cover,
            ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => pickImage(context),
            child: Text("Pick an Image"),
          ),
          SizedBox(height: 20),
          // Expanded(
          //   child: _similarImages.isEmpty
          //       ? Center(
          //           child: Text(
          //               "No similar images found. ${_similarImages.length}"))
          //       : GridView.builder(
          //           gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          //             crossAxisCount: 2,
          //             crossAxisSpacing: 4.0,
          //             mainAxisSpacing: 4.0,
          //           ),
          //           itemCount: _similarImages.length,
          //           itemBuilder: (context, index) {
          //             return CardItem(similarImage: _similarImages[index]);
          //           },
          //         ),
          // ),
          Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Detected Objec box: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              )),
          _similarImages.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            BoxScreen(similarImages: _similarImages),
                      ),
                    );
                  },
                  child: CardItem(similarImage: _similarImages[0]),
                )
              : Center(
                  child: Text("No similar images found."),
                ),
          SizedBox(
            height: 20,
          ),
          Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Detected faces: ',
                style: TextStyle(fontWeight: FontWeight.bold),
              )),

          Expanded(
            child: ListView.builder(
              itemCount: _faceSimilarImages.length,
              itemBuilder: (context, index) {
                int faceIndex = _faceSimilarImages.keys.elementAt(index);
                List<SimilarImage> faceImages = _faceSimilarImages[faceIndex]!;
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            BoxScreen(similarImages: faceImages),
                      ),
                    );
                  },
                  child: CardItem(similarImage: faceImages[0]),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

Future<File?> getFilePathFromId(String id) async {
  List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
    type: RequestType.image,
  );

  for (var album in albums) {
    List<AssetEntity> media = await album.getAssetListRange(
      start: 0,
      end: await album.assetCountAsync,
    );

    for (var asset in media) {
      if (asset.id == id) {
        File? file = await asset.originFile;
        return file;
      }
    }
  }
  return null;
}

class CardItem extends StatelessWidget {
  const CardItem({
    super.key,
    required SimilarImage similarImage,
  }) : _similarImage = similarImage;

  final SimilarImage _similarImage;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Center(
        child: FutureBuilder(
            future: getFilePathFromId(_similarImage.path),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                File? imageFile = snapshot.data as File?;
                if (imageFile != null) {
                  return Image.file(
                    imageFile,
                    fit: BoxFit.cover,
                    height: 100,
                    width: 100,
                  );
                } else {
                  return Text("Image not found");
                }
              } else {
                return Center(child: CircularProgressIndicator());
              }
            }),
      ),
      Text("Similarity: ${_similarImage.similarity.toStringAsFixed(2)}"),
    ]);
  }
}

class SimilarImage {
  final String path;
  final double similarity;
  SimilarImage({required this.path, required this.similarity});
}

extension ListReshape on List<double> {
  dynamic reshape(List<int> dims) {
    if (dims.length == 2) {
      int outer = dims[0];
      int inner = dims[1];
      if (length != outer * inner) {
        throw Exception("Cannot reshape list: incompatible dimensions 2D");
      }
      List<List<double>> result = [];
      for (int i = 0; i < outer; i++) {
        result.add(sublist(i * inner, (i + 1) * inner));
      }
      return result;
    } else if (dims.length == 4) {
      int outer1 = dims[0];
      int outer2 = dims[1];
      int inner1 = dims[2];
      int inner2 = dims[3];
      if (length != outer1 * outer2 * inner1 * inner2) {
        throw Exception("Cannot reshape list: incompatible dimensions 4D");
      }
      List<List<List<List<double>>>> result = [];
      for (int i = 0; i < outer1; i++) {
        List<List<List<double>>> outer2List = [];
        for (int j = 0; j < outer2; j++) {
          List<List<double>> inner1List = [];
          for (int k = 0; k < inner1; k++) {
            inner1List.add(sublist(
                (i * outer2 * inner1 * inner2) +
                    (j * inner1 * inner2) +
                    (k * inner2),
                (i * outer2 * inner1 * inner2) +
                    (j * inner1 * inner2) +
                    ((k + 1) * inner2)));
          }
          outer2List.add(inner1List);
        }
        result.add(outer2List);
      }
      return result;
    } else {
      throw Exception("Only 2D and 4D reshape are supported in this example");
    }
  }
}
