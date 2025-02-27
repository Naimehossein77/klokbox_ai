// import 'package:flutter/material.dart';
// import 'package:flutter_opencv/flutter_opencv.dart' as cv;
// import 'package:flutter_opencv/core/core.dart';
// import 'package:image_picker/image_picker.dart';
// import 'dart:io';

// void main() => runApp(MyApp());

// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       home: FaceDetectionScreen(),
//     );
//   }
// }

// class FaceDetectionScreen extends StatefulWidget {
//   @override
//   _FaceDetectionScreenState createState() => _FaceDetectionScreenState();
// }

// class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
//   File? _image;
//   final picker = ImagePicker();
//   List<Rect> _faces = [];

//   Future<void> _getImage() async {
//     final pickedFile = await picker.pickImage(source: ImageSource.gallery);

//     if (pickedFile != null) {
//       setState(() {
//         _image = File(pickedFile.path);
//       });
//       _detectFaces();
//     }
//   }

//   Future<void> _detectFaces() async {
//     if (_image == null) return;

//     final bytes = await _image!.readAsBytes();
//     final result = await cv.ImgProc.detectMultiScale(
//       bytes,
//       scaleFactor: 1.1,
//       minNeighbors: 5,
//       minSize: Size(30, 30),
//     );

//     setState(() {
//       _faces = result.map<Rect>((face) {
//         return Rect.fromLTWH(
//           face['x'].toDouble(),
//           face['y'].toDouble(),
//           face['width'].toDouble(),
//           face['height'].toDouble(),
//         );
//       }).toList();
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Face Detection'),
//       ),
//       body: Center(
//         child: _image == null
//             ? Text('No image selected.')
//             : Stack(
//                 children: [
//                   Image.file(_image!),
//                   ..._faces.map((face) {
//                     return Positioned(
//                       left: face.left,
//                       top: face.top,
//                       width: face.width,
//                       height: face.height,
//                       child: Container(
//                         decoration: BoxDecoration(
//                           border: Border.all(color: Colors.red, width: 2),
//                         ),
//                       ),
//                     );
//                   }).toList(),
//                 ],
//               ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _getImage,
//         tooltip: 'Pick Image',
//         child: Icon(Icons.add_a_photo),
//       ),
//     );
//   }
// }