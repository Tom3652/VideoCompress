import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_compress/src/progress_callback/compress_mixin.dart';
import 'package:video_compress/video_compress.dart';

abstract class IVideoCompress extends CompressMixin {}

class _VideoCompressImpl extends IVideoCompress {
  _VideoCompressImpl._() {
    initProcessCallback();
  }

  static _VideoCompressImpl? _instance;

  static _VideoCompressImpl get instance {
    return _instance ??= _VideoCompressImpl._();
  }

  static void _dispose() {
    _instance = null;
  }
}

// ignore: non_constant_identifier_names
IVideoCompress get VideoCompress => _VideoCompressImpl.instance;

extension Compress on IVideoCompress {
  void dispose() {
    _VideoCompressImpl._dispose();
  }

  Future<T?> _invoke<T>(String name, [Map<String, dynamic>? params]) async {
    T? result;
    try {
      result = params != null
          ? await channel.invokeMethod(name, params)
          : await channel.invokeMethod(name);
    } on PlatformException catch (e) {
      debugPrint('''Error from VideoCompress: 
      Method: $name
      $e''');
    }
    return result;
  }

  /// getByteThumbnail return [Future<Uint8List>],
  /// quality can be controlled by [quality] from 1 to 100,
  /// select the position unit in the video by [position] is milliseconds
  Future<Uint8List?> getByteThumbnail(
    String path, {
    int quality = 100,
    int position = -1,
  }) async {
    assert(quality > 1 || quality < 100);

    return await _invoke<Uint8List>('getByteThumbnail', {
      'path': path,
      'quality': quality,
      'position': position,
    });
  }

  /// getFileThumbnail return [Future<File>]
  /// quality can be controlled by [quality] from 1 to 100,
  /// select the position unit in the video by [position] is milliseconds
  Future<File> getFileThumbnail(
    String path, {
    int quality = 100,
    int position = -1,
  }) async {
    assert(quality > 1 || quality < 100);

    // Not to set the result as strong-mode so that it would have exception to
    // lead to the failure of compression
    final filePath = await (_invoke<String>('getFileThumbnail', {
      'path': path,
      'quality': quality,
      'position': position,
    }));

    final file = File(filePath!);

    return file;
  }

  /// get media information from [path]
  ///
  /// get media information from [path] return [Future<MediaInfo>]
  ///
  /// ## example
  /// ```dart
  /// final info = await _flutterVideoCompress.getMediaInfo(file.path);
  /// debugPrint(info.toJson());
  /// ```
  Future<MediaInfo> getMediaInfo(String path) async {
    // Not to set the result as strong-mode so that it would have exception to
    // lead to the failure of compression
    final jsonStr = await (_invoke<String>('getMediaInfo', {'path': path}));
    final jsonMap = json.decode(jsonStr!);
    return MediaInfo.fromJson(jsonMap);
  }

  /// Tells if the file [path] should be compressed or not.
  /// Sometimes you may have an already compressed file as input.
  ///
  /// This plugin export a new asset video to the target resolution,
  /// which means that if the target is higher than the input, the compression
  /// results in a larger file and lower quality, which is unwanted.
  Future<bool> _shouldCompress(String path) async {
    MediaInfo info = await getMediaInfo(path);
    int? width = info.width;
    int? height = info.height;
    bool shouldCompress = true;
    if (width != null && height != null) {
      shouldCompress =
          (width > 1100 && height > 640) || (height > 1100 && width > 640);
    }
    debugPrint("Should compress : $shouldCompress");
    return shouldCompress;
  }

  /// compress video from [path]
  /// compress video from [path] return [Future<MediaInfo>]
  ///
  /// you can choose its quality by [quality],
  /// determine whether to delete his source file by [deleteOrigin]
  /// optional parameters [startTime] [duration] [includeAudio] [frameRate]
  ///
  /// ## example
  /// ```dart
  /// final info = await _flutterVideoCompress.compressVideo(
  ///   file.path,
  ///   deleteOrigin: true,
  /// );
  /// debugPrint(info.toJson());
  /// ```
  Future<MediaInfo?> compressVideo({
    required String path,
    VideoQuality quality = VideoQuality.DefaultQuality,
    bool deleteOrigin = false,
    required String output,
    int? startTime,
    int? duration,
    bool shouldAvoidCompressionIfNotNeeded = true,
    bool? includeAudio,
    int frameRate = 30,
  }) async {
    bool shouldCompress =
        shouldAvoidCompressionIfNotNeeded ? await _shouldCompress(path) : true;
    if (shouldCompress) {
      if (isCompressing) {
        throw StateError('''VideoCompress Error: 
      Method: compressVideo
      Already have a compression process, you need to wait for the process to finish or stop it''');
      }

      if (compressProgress$.notSubscribed) {
        debugPrint('''VideoCompress: You can try to subscribe to the 
      compressProgress\$ stream to know the compressing state.''');
      }

      setProcessingStatus(true);
      setProcessingFile(path);
      final jsonStr = await _invoke<String>('compressVideo', {
        'path': path,
        'output': output,
        'quality': quality.index,
        'deleteOrigin': deleteOrigin,
        'startTime': startTime,
        'duration': duration,
        'includeAudio': includeAudio,
        'frameRate': frameRate,
      });

      setProcessingStatus(false);
      setProcessingFile("");

      if (jsonStr != null) {
        final jsonMap = json.decode(jsonStr);
        return MediaInfo.fromJson(jsonMap);
      } else {
        return null;
      }
    } else {
      return getMediaInfo(path);
    }
  }

  /// compress video from [path]
  /// compress video from [path] return [Future<MediaInfo>]
  ///
  /// you can choose its quality by [quality],
  /// determine whether to delete his source file by [deleteOrigin]
  /// optional parameters [startTime] [duration] [includeAudio] [frameRate]
  ///
  /// ## example
  /// ```dart
  /// final info = await _flutterVideoCompress.compressVideo(
  ///   file.path,
  ///   deleteOrigin: true,
  /// );
  /// debugPrint(info.toJson());
  /// ```
  Future<MediaInfo?> compressVideoAndroid(
      {required String path,
      required String output,
      required int maxSize,
      int bitrate = 1000000,
      int keyFrameInterval = 1,
      int? startTime,
      int? duration,
      bool includeAudio = true,
      int frameRate = 30,
      int audioBitRate = 128000,
      int channels = 2,
      int sampleRate = 44100,
        double bitrateLowResFactor = 5.5,
        bool isLowRes = false}) async {
    if (isCompressing) {
      throw StateError('''VideoCompress Error: 
      Method: compressVideo
      Already have a compression process, you need to wait for the process to finish or stop it''');
    }

    if (compressProgress$.notSubscribed) {
      debugPrint('''VideoCompress: You can try to subscribe to the 
      compressProgress\$ stream to know the compressing state.''');
    }

    setProcessingStatus(true);
    setProcessingFile(path);
    if (isLowRes) {
      bitrate = (bitrate / bitrateLowResFactor).floor();
    }
    final jsonStr = await _invoke<String>('compressVideoAndroid', {
      'path': path,
      'output': output,
      'bitrate': bitrate,
      "maxSize": maxSize,
      "keyFrameInterval": keyFrameInterval,
      'startTime': startTime,
      'duration': duration,
      'includeAudio': includeAudio,
      'frameRate': frameRate,
      "channels": channels,
      "audioBitRate": audioBitRate,
      "sampleRate": sampleRate
    });

    setProcessingStatus(false);
    setProcessingFile("");

    if (jsonStr != null && !jsonStr.contains("error")) {
      final jsonMap = json.decode(jsonStr);
      return MediaInfo.fromJson(jsonMap);
    } else {
      return null;
    }
  }

  /// The bit rate should be between 500 000 - 5 000 000 (500 kbps - 5000 kbps)
  /// for lower and higher quality.
  /// Recommended quality for mobile post is between 1 000 000 - 2 500 000 depending
  /// on the original video file quality and compression.
  /// Can be between 100 000 and 500 000 for a low res vid.
  ///
  /// The lower the bitrate will be, the lower the video size/quality will be.
  Future<String?> compressVideoIOS(
      {required String input,
      required String output,
      required double width,
      required double height,
      int bitrate = 1000000,
        double bitrateLowResFactor = 5.5,
      int frameRate = 30,
      bool isLowRes = false}) async {
    if (isCompressing) {
      throw StateError('''VideoCompress Error: 
      Method: compressVideo
      Already have a compression process, you need to wait for the process to finish or stop it''');
    }

    if (compressProgress$.notSubscribed) {
      debugPrint('''VideoCompress: You can try to subscribe to the 
      compressProgress\$ stream to know the compressing state.''');
    }

    setProcessingStatus(true);
    setProcessingFile(input);
    if (isLowRes) {
      bitrate = (bitrate / bitrateLowResFactor).floor();
    }
    String? result;
    try {
      result = await _invoke("compressVideoIOS", {
        "inputFile": input,
        "outputFile": output,
        "width": width,
        "height": height,
        "bitrate": bitrate,
        "frameRate": frameRate,
      });
      setProcessingStatus(false);
      setProcessingFile("");
    } catch (e) {
      print("error while comressing ios video : $e");
    }
    return result;
  }

  /// stop compressing the file that is currently being compressed.
  /// If there is no compression process, nothing will happen.
  Future<void> cancelCompression() async {
    await _invoke<void>('cancelCompression');
  }

  /// delete the cache folder, please do not put other things
  /// in the folder of this plugin, it will be cleared
  Future<bool?> deleteAllCache() async {
    return await _invoke<bool>('deleteAllCache');
  }

  Future<void> setLogLevel(int logLevel) async {
    return await _invoke<void>('setLogLevel', {
      'logLevel': logLevel,
    });
  }
}
