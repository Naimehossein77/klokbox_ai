import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> createVideo(List<String> imagePaths) async {
  // Request permissions
  await Permission.storage.request();

  Directory dir;
  if (Platform.isAndroid) {
    dir = Directory('/storage/emulated/0/Download');
  } else if (Platform.isIOS) {
    dir = await getApplicationDocumentsDirectory();
  } else {
    throw UnsupportedError("This platform is not supported");
  }

  // Ensure directory exists
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final outputPath = "${dir.path}/output.mp4";
  final fileListPath = "${dir.path}/file_list.txt";

  // ✅ Fix: Check if images exist before writing file_list.txt
  for (String path in imagePaths) {
    if (!File(path).existsSync()) {
      print("❌ Image Not Found: $path");
      return;
    }
  }

  // ✅ Fix: Create file_list.txt correctly
  File file = File(fileListPath);
  String content =
      imagePaths.map((path) => "file '$path'\nduration 2").join("\n");
  await file.writeAsString(content);

  // ✅ Fix: Print the generated file_list.txt for debugging
  print("✅ file_list.txt created at: $fileListPath");
  print("🔍 file_list.txt content:\n$content");

  // ✅ Fix: Ensure file_list.txt exists before running FFmpeg
  if (!File(fileListPath).existsSync()) {
    print("❌ file_list.txt not found!");
    return;
  }

  // FFmpeg command to create video with fade transitions
  // String ffmpegCommand = '''
  //   -f concat -safe 0 -i "$fileListPath" -vf "fade=t=in:st=0:d=1,fade=t=out:st=1.5:d=1" -c:v libx264 -r 30 -pix_fmt yuv420p "$outputPath"
  // ''';

  String ffmpegCommand = '';
  for (int i = 0; i < imagePaths.length; i++) {
    ffmpegCommand += '-loop 1 -framerate 24 -t 2 -i "${imagePaths[i]}" ';
  }
  ffmpegCommand += '-filter_complex "';
  for (int i = 0; i < imagePaths.length; i++) {
    ffmpegCommand +=
        '[$i:v]scale=1920:1080:force_original_aspect_ratio=increase,setsar=1:1,crop=1920:1080[v$i];';
  }
  for (int i = 0; i < imagePaths.length; i++) {
    ffmpegCommand += '[v$i]';
  }
  ffmpegCommand +=
      'concat=n=${imagePaths.length}:v=1:a=0[outv]" -map "[outv]" ';
  ffmpegCommand += '-pix_fmt yuv420p -y "$outputPath"';

  print("🔍 Running FFmpeg Command:\n$ffmpegCommand");

  // Run FFmpeg
  final session = await FFmpegKit.execute(ffmpegCommand);
  final logs = await session.getLogs();
  final returnCode = await session.getReturnCode();

  // Print FFmpeg logs
  logs.forEach((log) => print("FFmpeg Log: ${log.getMessage()}"));

  if (returnCode?.isValueSuccess() == true) {
    print(
        "✅ Video Processing Completed Successfully! Video saved at: $outputPath");
    // await ImageGallerySaver.saveFile(outputPath);
    Gal.putVideo(outputPath);
    // Show a snackbar with success message
    Fluttertoast.showToast(msg: 'Video saved at $outputPath');
  } else {
    print("❌ FFmpeg Failed with Return Code: ${returnCode?.getValue()}");
    print("📜 Error Details: ${await session.getFailStackTrace()}");
  }
}
