import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/constants.dart';

class MimoTtsException implements Exception {
  const MimoTtsException({
    required this.message,
    this.statusCode,
    this.isRetryable = false,
  });

  final String message;
  final int? statusCode;
  final bool isRetryable;

  @override
  String toString() => 'MimoTtsException($statusCode, $message)';
}

class MimoTtsApiClient {
  MimoTtsApiClient({http.Client? client, Uri? endpoint})
    : _client = client ?? http.Client(),
      endpoint = endpoint ?? Uri.parse(AppConstants.mimoBaseUrl);

  final http.Client _client;
  final Uri endpoint;

  Map<String, String> buildHeaders(String apiKey) {
    return {'api-key': apiKey, 'Content-Type': 'application/json'};
  }

  Map<String, dynamic> buildRequestBody({
    required String text,
    required String voiceId,
    required String speedPrompt,
  }) {
    return {
      'model': AppConstants.mimoModel,
      'messages': [
        {
          'role': 'user',
          'content':
              '${AppConstants.defaultNarrationPrompt} $speedPrompt 请保持长篇小说旁白的连贯感。',
        },
        {'role': 'assistant', 'content': text},
      ],
      'audio': {'format': 'wav', 'voice': voiceId},
      'stream': false,
    };
  }

  Future<Uint8List> synthesize({
    required String apiKey,
    required String text,
    required String voiceId,
    required String speedPrompt,
  }) async {
    http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: buildHeaders(apiKey),
            body: jsonEncode(
              buildRequestBody(
                text: text,
                voiceId: voiceId,
                speedPrompt: speedPrompt,
              ),
            ),
          )
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const MimoTtsException(message: '朗读准备超时，请稍后重试。', isRetryable: true);
    } on SocketException {
      throw const MimoTtsException(message: '网络不可用，请稍后重试。', isRetryable: true);
    } on HandshakeException {
      throw const MimoTtsException(
        message: '安全连接失败，请稍后重试或检查系统网络。',
        isRetryable: true,
      );
    } on http.ClientException catch (error) {
      final String message = error.message.toLowerCase();
      if (message.contains('connection closed') ||
          message.contains('connection reset')) {
        throw const MimoTtsException(
          message: '朗读连接被中断，已缩短单段字数，请重试。',
          isRetryable: true,
        );
      }
      throw MimoTtsException(
        message: '朗读请求失败：${error.message}',
        isRetryable: true,
      );
    } on Exception {
      throw const MimoTtsException(message: '朗读请求失败，请稍后重试。', isRetryable: true);
    }

    if (response.statusCode != 200) {
      throw _exceptionForStatus(
        response.statusCode,
        _extractErrorMessage(response.body),
      );
    }

    final String base64Audio = parseAudioData(response.body);
    return base64Decode(base64Audio);
  }

  String parseAudioData(String responseBody) {
    final dynamic decoded = jsonDecode(responseBody);
    final List<dynamic>? choices =
        (decoded as Map<String, dynamic>)['choices'] as List<dynamic>?;
    final Map<String, dynamic>? message =
        choices?.firstOrNull as Map<String, dynamic>?;
    final Map<String, dynamic>? audio =
        message?['message'] as Map<String, dynamic>?;
    final dynamic data = (audio?['audio'] as Map<String, dynamic>?)?['data'];

    if (data is! String || data.isEmpty) {
      throw const MimoTtsException(message: 'MiMo 返回中没有音频数据');
    }

    return data;
  }

  String _extractErrorMessage(String responseBody) {
    try {
      final dynamic decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final dynamic error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final dynamic message = error['message'] ?? error['msg'];
          if (message is String && message.isNotEmpty) {
            return message;
          }
        }
      }
    } catch (_) {}
    return '';
  }

  MimoTtsException _exceptionForStatus(int statusCode, String rawMessage) {
    switch (statusCode) {
      case 401:
        return const MimoTtsException(
          statusCode: 401,
          message: 'API Key 无效或认证失败。',
        );
      case 402:
        return const MimoTtsException(
          statusCode: 402,
          message: 'MiMo 账户余额不足，请充值后再试。',
        );
      case 403:
        return const MimoTtsException(
          statusCode: 403,
          message: '当前地区不支持或请求被拒绝。',
        );
      case 421:
        return const MimoTtsException(
          statusCode: 421,
          message: '这一段内容被安全策略拦截，暂时无法朗读。',
        );
      case 429:
        return const MimoTtsException(
          statusCode: 429,
          message: '请求太频繁了，稍等一下再继续。',
          isRetryable: true,
        );
      case 500:
      case 503:
        return MimoTtsException(
          statusCode: statusCode,
          message: rawMessage.isEmpty ? '服务暂时不可用，请稍后重试。' : rawMessage,
          isRetryable: true,
        );
      default:
        return MimoTtsException(
          statusCode: statusCode,
          message: rawMessage.isEmpty ? '朗读请求失败，请稍后重试。' : rawMessage,
          isRetryable: statusCode >= 500,
        );
    }
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
