import 'package:flutter/services.dart';

import '../core/constants.dart';

typedef SharedTxtListener = Future<void> Function(PickedTxtFile file);

class PickedTxtFile {
  const PickedTxtFile({
    required this.fileName,
    required this.text,
    required this.encoding,
    required this.sizeBytes,
  });

  factory PickedTxtFile.fromPlatformMap(Map<dynamic, dynamic> result) {
    final String? error = result['error'] as String?;
    if (error != null && error.isNotEmpty) {
      throw PlatformException(code: 'READ_FAILED', message: error);
    }

    return PickedTxtFile(
      fileName: result['fileName'] as String? ?? 'TXT 小说',
      text: result['text'] as String? ?? '',
      encoding: result['encoding'] as String? ?? 'utf-8',
      sizeBytes: (result['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  final String fileName;
  final String text;
  final String encoding;
  final int sizeBytes;
}

class NativeFileService {
  NativeFileService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(AppConstants.methodChannelName);

  final MethodChannel _channel;
  SharedTxtListener? _sharedTxtListener;

  Future<PickedTxtFile?> pickTxtFile() async {
    final Map<dynamic, dynamic>? result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('pickTxtFile');

    if (result == null) {
      return null;
    }

    return PickedTxtFile.fromPlatformMap(result);
  }

  Future<PickedTxtFile?> consumeSharedTxtFile() async {
    final Map<dynamic, dynamic>? result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('consumeSharedTxtFile');

    if (result == null) {
      return null;
    }

    return PickedTxtFile.fromPlatformMap(result);
  }

  void setSharedTxtListener(SharedTxtListener listener) {
    _sharedTxtListener = listener;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  void clearSharedTxtListener() {
    _sharedTxtListener = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'sharedTxtAvailable') {
      throw MissingPluginException('Unknown native callback: ${call.method}');
    }

    final PickedTxtFile? file = await consumeSharedTxtFile();
    if (file != null) {
      await _sharedTxtListener?.call(file);
    }
  }
}
