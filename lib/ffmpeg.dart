import 'dart:io';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';

Future<void> createVideo(List<String> imagePaths) async {
  Directory dir;
  if (Platform.isAndroid) {
    dir = Directory('/storage/emulated/0/Download');
  } else if (Platform.isIOS) {
    dir = await getApplicationDocumentsDirectory();
  } else {
    throw UnsupportedError("This platform is not supported");
  }
  final outputPath = "${dir.path}/output.mp4";

  // Prepare input files
  String fileListPath = "${dir.path}/file_list.txt";
  File file = File(fileListPath);
  String content =
      imagePaths.map((path) => "file '$path'\nduration 2").join("\n");
  await file.writeAsString(content);

  // FFmpeg command to create video with fade transitions
  String ffmpegCommand = '''
    -f concat -safe 0 -i "$fileListPath" -vf "fade=t=in:st=0:d=1,fade=t=out:st=1.5:d=1" -c:v libx264 -r 30 -pix_fmt yuv420p "$outputPath"
  ''';

  // Run FFmpeg
  await FFmpegKit.execute(ffmpegCommand).then((session) async {
    print((await session.getLogs()).map((log) => log.getMessage()).join("\n"));
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      print("Video processing completed successfully.");
    } else {
      print("Video processing failed with return code: $returnCode");
    }
  });

  print("Video Created at: $outputPath");
}
