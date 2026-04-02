
import 'package:flutter/foundation.dart';

class MediaInfo {
  String? path;
  String? title;
  String? author;
  int? width;
  int? height;

  /// [Android] API level 17
  int? orientation;

  /// bytes
  int? fileSize; // file size
  /// microsecond
  double? duration;
  bool? isCancel;

  bool? get isLandscape => orientation == null ? null : (orientation! / 90) % 2 != 0;

  MediaInfo({
    required this.path,
    this.title,
    this.author,
    this.width,
    this.height,
    this.orientation,
    this.fileSize,
    this.duration,
    this.isCancel,
  });

  MediaInfo.fromJson(Map<String, dynamic> json) {
    debugPrint("VideoCompress: Json is : $json");
    path = json['path'];
    title = json['title'];
    author = json['author'];
    width = _toInt(json['width']);
    height = _toInt(json['height']);
    orientation = _toInt(json['orientation']);
    fileSize = _toInt(json['fileSize']);
    duration = double.tryParse('${json['duration']}');
    isCancel = json['isCancel'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['path'] = this.path;
    data['title'] = this.title;
    data['author'] = this.author;
    data['width'] = this.width;
    data['height'] = this.height;
    if (this.orientation != null) {
      data['orientation'] = this.orientation;
    }
    data['fileSize'] = this.fileSize;
    data['duration'] = this.duration;
    if (this.isCancel != null) {
      data['isCancel'] = this.isCancel;
    }
    return data;
  }

  @override
  String toString() {
    return "MediaInfo - width: $width - height $height - orientation $orientation - landscape : $isLandscape";
  }

  int? _toInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse('$value') ?? double.tryParse('$value')?.round();
  }
}
