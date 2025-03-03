import 'package:flutter/material.dart';
import 'package:klokbox_ai/main.dart';

import 'ffmpeg.dart';

class BoxScreen extends StatelessWidget {
  final List<SimilarImage> similarImages;

  BoxScreen({required this.similarImages});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Box Screen'),
        actions: [
          IconButton(
            icon: Icon(Icons.create),
            onPressed: () {
              // Create video from similar images
              createVideo(similarImages.map((image) => image.path).toList());
            },
          ),
        ],
      ),
      body: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 4.0,
          mainAxisSpacing: 4.0,
        ),
        itemCount: similarImages.length,
        itemBuilder: (context, index) {
          return CardItem(similarImage: similarImages[index]);
        },
      ),
    );
  }
}
