import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

// Add this method to your FaceRecognitionService class
Future<List<Uint8List>> cropFaces(String filePath) async {
  try {
    final img.Image? originalImage = img.decodeImage(File(filePath).readAsBytesSync());
    if (originalImage == null) {
      throw Exception('Failed to decode image');
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
    final inputImage = InputImage.fromFilePath(filePath);
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: false,
        enableClassification: false,
        enableTracking: false,
      ),
    );

    final List<Face> faces =
        await faceDetector.processImage(inputImage);

    if (faces.isEmpty) {
      throw Exception('No faces detected in the image');
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
