import 'package:flutter/services.dart';

/// Opens the native iOS share sheet for a generated local file.
class FileShare {
  FileShare._();

  static const MethodChannel _channel = MethodChannel('cleanify/file_share');

  static Future<bool> share(String path) async =>
      await _channel.invokeMethod<bool>('shareFile', {'path': path}) ?? false;
}
