import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
  final ImagePicker _picker = ImagePicker();
  List<double>? _queryFeature;
  List<SimilarImage> _similarImages = [];
  Database? _database;
  int _processed = 0;

  @override
  void initState() {
    super.initState();
    loadModel();
    initializeDatabase();
  }

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/mobilenet_v2.tflite');
      print('Model loaded successfully');
    } catch (e) {
      print('Error loading model: $e');
    }
  }

  Future<void> initializeDatabase() async {
    // await deleteDatabase(join(await getDatabasesPath(), 'image_features.db'));
    _database = await openDatabase(
      join(await getDatabasesPath(), 'image_features.db'),
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE features(id TEXT PRIMARY KEY, path TEXT, feature TEXT)',
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
      // Get all albums
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image, // Only get images
      );

      if (albums.isEmpty) return;

      // Get recent album (usually "Recent" or "All Photos")
      final recentAlbum = albums[0];

      // Load all images in chunks to avoid memory issues
      int page = 0;
      const int pageSize = 50;
      bool hasMore = true;

      while (hasMore) {
        List<AssetEntity> media = await recentAlbum.getAssetListPaged(
          page: page,
          size: pageSize,
        );

        print(media.length);

        if (media.isEmpty || page > 2) {
          hasMore = false;
          break;
        }

        for (var asset in media) {
          try {
            // Check if the feature is already stored in the database
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
              continue; // Skip if feature already exists
            }

            File? file = await asset.file;

            if (file != null) {
              try {
                Uint8List? bytes = await FlutterImageCompress.compressWithFile(
                  file.path,
                  minWidth: 224,
                  minHeight: 224,
                  quality: 85,
                );
                if (bytes != null) {
                  List<double> feature = await extractFeatureVector(bytes);
                  await storeFeatureInDatabase(asset.id, file.path, feature);
                }
                print('object');
              } finally {
                if (await file.exists()) {
                  print(file.path);
                  await file.delete();
                }
              }
            }
            // if (file != null) {
            //   Uint8List bytes = await file.readAsBytes();
            //   List<double> feature = await extractFeatureVector(bytes);
            //   await storeFeatureInDatabase(asset.id, file.path, feature);
            // }
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

  Future<void> pickImage() async {
    final XFile? imageFile =
        await _picker.pickImage(source: ImageSource.gallery);
    if (imageFile != null) {
      final file = File(imageFile.path);
      final bytes;
      Uint8List? compressedBytes = await FlutterImageCompress.compressWithFile(
        file.path,
        minWidth: 224,
        minHeight: 224,
        quality: 85,
      );
      if (compressedBytes != null) {
        bytes = compressedBytes;
      } else {
        bytes = await file.readAsBytes();
      }
      setState(() {
        _queryFeature = null;
        _similarImages = [];
      });
      _queryFeature = await extractFeatureVector(bytes);
      findSimilarImages();
    }
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
    if (_interpreter == null) {
      throw Exception('Model is not loaded');
    }
    Float32List input = preprocessImage(imageData);
    var inputTensor = input.buffer.asFloat32List().reshape([1, 224, 224, 3]);
    var outputBuffer = List.filled(1001, 0.0).reshape([1, 1001]);
    _interpreter!.run(inputTensor, outputBuffer);

    // Normalize the output vector
    List<double> features = List<double>.from(outputBuffer[0]);
    double maxVal = features.reduce(max);
    double minVal = features.reduce(min);

    // Normalize to range [0,1]
    if (maxVal != minVal) {
      features = features.map((e) => (e - minVal) / (maxVal - minVal)).toList();
    }

    // print('Feature vector length: ${features}');
    return features;
  }

  double cosineSimilarity(List<double> vectorA, List<double> vectorB) {
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < vectorA.length; i++) {
      dotProduct += vectorA[i] * vectorB[i];
      normA += vectorA[i] * vectorA[i];
      normB += vectorB[i] * vectorB[i];
      // print(normB);
    }
    // print(normA);
    // print(normB);
    double norm = (sqrt(normA) * sqrt(normB));
    // debugPrint('Norm: $norm');
    if (norm == 0) {
      return 0.0;
    }

    return dotProduct / norm;
  }

  Future<void> findSimilarImages() async {
    if (_queryFeature == null) return;
    List<Map<String, dynamic>> maps = await _database!.query('features');
    // print(maps);
    List<SimilarImage> results = [];
    // _queryFeature = bytesToFeature(featureToBytes(_queryFeature!));
    for (var map in maps) {
      List<double> feature =
          (jsonDecode(map['feature']) as List).cast<double>();
      // print('Feature length: ${feature.length}');
      // print('Query feature length: ${_queryFeature?.length}');
      // print(feature);
      double similarity = cosineSimilarity(_queryFeature!, feature);
      // print(similarity);
      if (similarity > 0.15) {
        results.add(SimilarImage(path: map['path'], similarity: similarity));
      }
    }
    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    setState(() {
      _similarImages = results.take(10).toList();
    });
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
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: pickImage,
            child: Text("Pick an Image"),
          ),
          SizedBox(height: 20),
          Expanded(
            child: _similarImages.isEmpty
                ? Center(child: Text("No similar images found."))
                : ListView.builder(
                    itemCount: _similarImages.length,
                    itemBuilder: (context, index) {
                      // File imageFile = File(_similarImages[index].path);
                      return CardItem(similarImage: _similarImages[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class CardItem extends StatelessWidget {
  const CardItem({
    super.key,
    required SimilarImage similarImage,
  }) : _similarImage = similarImage;

  final SimilarImage _similarImage;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: _similarImage.path.isNotEmpty
          ? Image.file(File(_similarImage.path))
          : Text("Image not found"),
      subtitle:
          Text("Similarity: ${_similarImage.similarity.toStringAsFixed(2)}"),
    );
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
      if (this.length != outer * inner) {
        throw Exception("Cannot reshape list: incompatible dimensions");
      }
      List<List<double>> result = [];
      for (int i = 0; i < outer; i++) {
        result.add(this.sublist(i * inner, (i + 1) * inner));
      }
      return result;
    } else if (dims.length == 4) {
      int outer1 = dims[0];
      int outer2 = dims[1];
      int inner1 = dims[2];
      int inner2 = dims[3];
      if (this.length != outer1 * outer2 * inner1 * inner2) {
        throw Exception("Cannot reshape list: incompatible dimensions");
      }
      List<List<List<List<double>>>> result = [];
      for (int i = 0; i < outer1; i++) {
        List<List<List<double>>> outer2List = [];
        for (int j = 0; j < outer2; j++) {
          List<List<double>> inner1List = [];
          for (int k = 0; k < inner1; k++) {
            inner1List.add(this.sublist(
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
