import 'package:flutter/material.dart';
import 'package:klokbox_ai/main.dart';
import 'package:photo_manager/photo_manager.dart';

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
            onPressed: () async {
              // Create video from similar images
              List<String> imagePaths = [];
              for (var image in similarImages) {
                String? path = await findImagePathFromId(image.path);
                if (path != null) {
                  imagePaths.add(path);
                }
              }
              createVideo(imagePaths);
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

  Future<String?> findImagePathFromId(String imageId) async {
    final List<AssetPathEntity> albums =
        await PhotoManager.getAssetPathList();
    for (final album in albums) {
      final List<AssetEntity> images = await album.getAssetListRange(
          start: 0, end: await album.assetCountAsync);
      for (final image in images) {
        if (image.id == imageId) {
          return (await image.file)?.path;
        }
      }
    }
    return null;
  }
}
