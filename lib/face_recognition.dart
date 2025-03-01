import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

// Add this method to your FaceRecognitionService class
Future<List<Uint8List>> cropFaces(Uint8List imageBytes) async {
  try {
    final img.Image? originalImage;
    try {
      originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        throw Exception('Failed to decode image');
      }
    } catch (e) {
      // throw Exception('Failed to read or decode image: $e');
      rethrow;
    }

    // if (originalImage == null) {
    //   throw Exception('Failed to decode image');
    // }

    // Detect faces
    // final inputImage = InputImage.fromBytes(
    //   bytes: imageBytes,
    //   metadata: InputImageMetadata(
    //     size: Size(originalImage.width.toDouble(),
    //         originalImage.height.toDouble()),
    //     rotation: InputImageRotation.rotation0deg,
    //     format: Platform.isAndroid
    //         ? InputImageFormat.nv21 // Android format
    //         : InputImageFormat.bgra8888, // iOS format
    //     bytesPerRow: originalImage.width,
    //   ),
    // );
    final tempDir = await Directory.systemTemp.createTemp();
    final filePath = '${tempDir.path}/temp_image.jpg';
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    final inputImage = InputImage.fromFilePath(filePath);
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: false,
        enableClassification: false,
        enableTracking: false,
      ),
    );

    final stopwatch = Stopwatch()..start();
    final List<Face> faces = await faceDetector.processImage(inputImage);
    stopwatch.stop();
    print('Face detection took: ${stopwatch.elapsedMilliseconds} ms');

    if (faces.isEmpty) {
      // throw Exception('No faces detected in the image');
      print('No Faces detected in ${file.path}');
    } else {
      print('Detected ${faces.length} faces');
    }

    // Crop each face
    List<Uint8List> croppedFaces = [];
    for (Face face in faces) {
      // Get face bounding box
      int left = face.boundingBox.left.round();
      int top = face.boundingBox.top.round();
      int width = face.boundingBox.width.round();
      int height = face.boundingBox.height.round();

      // Ensure coordinates are within image bounds
      left = left.clamp(0, originalImage.width - 1);
      top = top.clamp(0, originalImage.height - 1);
      width = width.clamp(0, originalImage.width - left);
      height = height.clamp(0, originalImage.height - top);

      // Crop the face
      final img.Image croppedImage = img.copyCrop(
        originalImage,
        x: left,
        y: top,
        width: width,
        height: height,
      );

      // Convert cropped image to bytes
      final List<int> croppedBytes = img.encodeJpg(croppedImage);
      croppedFaces.add(Uint8List.fromList(croppedBytes));
    }

    return croppedFaces;
  } catch (e) {
    throw Exception('Failed to crop faces: $e');
  }
}
