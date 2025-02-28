import 'package:flutter/material.dart';
import 'package:klokbox_ai/main.dart';

class BoxScreen extends StatelessWidget {
  final List<SimilarImage> similarImages;

  BoxScreen({required this.similarImages});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Box Screen'),
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
