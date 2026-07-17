import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_compress_example/widgets/video_player_app.dart';

import 'media_manager.dart';

class CompressPage extends StatefulWidget {
  final String? file;
  const CompressPage({super.key, this.file});

  @override
  State<CompressPage> createState() => _CompressPageState();
}

class _CompressPageState extends State<CompressPage> {
  //final Uploader _uploader = Uploader();

  String originFile = "";
  String compressedFile = "";

  MediaManager mediaManager = MediaManager();
  VideoInfo infoOrigin = VideoInfo();
  VideoInfo infoCompressed = VideoInfo();

  final MethodChannel compressChannel = const MethodChannel("VideoCompress");

  Future<void> init() async {
    originFile = widget.file ?? "";
    if(originFile.isNotEmpty) {
      infoOrigin = await mediaManager.getInfo(originFile);
      setState(() {

      });
    }
  }
  @override
  void initState() {
    init();
    super.initState();
  }

  @override
  void dispose() {
    if (compressedFile.isNotEmpty) {
      print("delete file : $compressedFile");
      File(compressedFile).deleteSync();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: widget.file == null ? FloatingActionButton(
        onPressed: onNewPostTap,
        child: const Icon(CupertinoIcons.add),
      ) : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            originFile.isNotEmpty
                ? media(file: originFile, info: infoOrigin, width: 500)
                : const SizedBox(),
            const SizedBox(height: 30),
            compressedFile.isNotEmpty
                ? media(
                    file: compressedFile,
                    info: infoCompressed,
                    mute: false,
                    width: 200)
                : const SizedBox(),
            const SizedBox(height: 30),
            Center(
              child: CupertinoButton(
                color: Colors.blue,
                onPressed: onCompress,
                child: const Text("Compress"),
              ),
            ),
            const SizedBox(height: 30),
            Center(
              child: CupertinoButton(
                color: Colors.redAccent,
                onPressed: onSave,
                child: const Text("Save"),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget media({
    required String file,
    required VideoInfo info,
    bool mute = true,
    required double width,
  }) {
    bool video = mediaManager.isVideo(file);
    print(
        "Origin info : ${"Width : ${info.width} |  Height : ${info.height} |  Size : ${info.size}"}");
    print("\n-----------------------------\n");
    return Column(
      children: [
        if (video)
          SizedBox(
            width: width,
            child: VideoPlayerApp(
              file: file,
              mute: mute,
              shouldLoop: true,
            ),
          ),
        if (!video) Image.file(File(file)),
        const SizedBox(height: 10),
        Text(
          "Width : ${info.width} |  Height : ${info.height} |  Size : ${info.size}",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        )
      ],
    );
  }

  Future<void> onNewPostTap() async {
    final xfile = await ImagePicker().pickMedia();
    if (xfile != null) {
      setState(() {
        originFile = "";
        compressedFile = "";
      });
      await Future.delayed(const Duration(seconds: 1));
      infoOrigin = await mediaManager.getInfo(xfile.path);
      setState(() {
        originFile = xfile.path;
      });
    }
  }

  Future<void> onCompress() async {
    if (originFile.isNotEmpty) {
      if (compressedFile.isNotEmpty) {
        print("delete file : $compressedFile");
        File(compressedFile).deleteSync();
      }
      setState(() {
        compressedFile = "";
      });

      bool video = mediaManager.isVideo(originFile);
      if (video) {
        /*MediaInfo? mediaInfo = await VideoCompress.compressVideo(
          originFile,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
        );*/
        final dir = await getTemporaryDirectory();
        File file = File(
            "${dir.path}/compress_video${DateTime.now().millisecondsSinceEpoch}.mp4");

        bool isLowRes = true;
        double ratio = infoOrigin.height / infoOrigin.width;

        double newHeight = 0;
        double newWidth = 0;

        double maxSize = isLowRes ? 480 : 960;

        print("ratio : $ratio");
        if (ratio <= 1) {
          newWidth = min(maxSize, infoOrigin.width.floorToDouble());
          newHeight = newWidth * ratio;
        } else {
          newHeight = min(maxSize, infoOrigin.height.floorToDouble());
          newWidth = newHeight / ratio;
        }
        print("new width : $newWidth");
        print("new height : $newHeight");

        String? output = Platform.isIOS
            ? await VideoCompress.compressVideoIOS(
                input: originFile,
                output: file.path,
                bitrate: 1000000,
                bitrateLowResFactor: 5.5,
                width: newWidth,
                height: newHeight,
                isLowRes: isLowRes)
            : (await VideoCompress.compressVideoAndroid(
                path: originFile,
                output: file.path,
                maxSize: maxSize.floor(),
              ))
                ?.path;

        /*await compressChannel.invokeMethod("compressVideo", {
          "inputFile": originFile,
          "outputFile": file.path,
          "width": newWidth,
          "height": newHeight,
          "bitrate": 2500000, // 1000000,
          "frameRate": 30,
          //"outputFile": file.path,
          "quality": 2,
          "usePreset": false,
        });*/
        print("compressed result : $output");
        if (output != null) {
          infoCompressed = await mediaManager.getInfo(output);
          //infoCompressed.height = mediaInfo!.height!;
          //infoCompressed.width = mediaInfo!.width!;
          //print("file compressed : ${temp.path}");
          setState(() {
            compressedFile = output; // mediaInfo!.path!;
          });
        }
      } /*else {
        Uint8List? data;
        try {
          data = await FlutterImageCompress.compressWithFile(originFile,
              minHeight: 1280, minWidth: 1280, quality: 95);
          if (data != null) {
            final tempDir = await getTemporaryDirectory();

            // Create a unique file path in the temporary directory
            final tempFile = File(
                '${tempDir.path}/temp_file_${DateTime.now().millisecondsSinceEpoch}.tmp');

            // Write the bytes to the file
            await tempFile.writeAsBytes(data);
            setState(() {
              compressedFile = tempFile.path;
            });
          }
        } catch (e) {}
      }*/
    }
  }




  void onSave() {
    mediaManager.onSave(compressedFile);
  }
}
