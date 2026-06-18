import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:novel_tts_reader/services/mimo_tts_api_client.dart';

void main() {
  group('MimoTtsApiClient', () {
    test('builds headers with api-key', () {
      final client = MimoTtsApiClient(
        client: _FakeClient((_) async {
          throw UnimplementedError();
        }),
      );

      final headers = client.buildHeaders('demo-key');
      expect(headers['api-key'], 'demo-key');
      expect(headers['Content-Type'], 'application/json');
    });

    test('builds request body with fixed model and assistant text', () {
      final client = MimoTtsApiClient(
        client: _FakeClient((_) async {
          throw UnimplementedError();
        }),
      );

      final body = client.buildRequestBody(
        text: '这里是正文',
        voiceId: '冰糖',
        speedPrompt: '语速正常，段落停顿自然。',
      );

      expect(body['model'], 'mimo-v2.5-tts');
      expect((body['audio'] as Map<String, dynamic>)['format'], 'mp3');
      final List<dynamic> messages = body['messages'] as List<dynamic>;
      expect(messages[0]['role'], 'user');
      expect(messages[1]['role'], 'assistant');
      expect(messages[1]['content'], '这里是正文');
    });

    test('parses base64 audio from a successful response', () async {
      final String encoded = base64Encode([1, 2, 3, 4]);
      final client = MimoTtsApiClient(
        client: _FakeClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'audio': {'data': encoded},
                  },
                },
              ],
            }),
            200,
          ),
        ),
      );

      final bytes = await client.synthesize(
        apiKey: 'demo-key',
        text: '测试文本',
        voiceId: '冰糖',
        speedPrompt: '语速正常，段落停顿自然。',
      );

      expect(bytes, [1, 2, 3, 4]);
    });

    test('maps 401 to a readable exception', () async {
      final client = MimoTtsApiClient(
        client: _FakeClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'unauthorized'},
            }),
            401,
          ),
        ),
      );

      await expectLater(
        client.synthesize(
          apiKey: 'bad-key',
          text: '测试文本',
          voiceId: '冰糖',
          speedPrompt: '语速正常，段落停顿自然。',
        ),
        throwsA(
          isA<MimoTtsException>().having(
            (error) => error.message,
            'message',
            'API Key 无效或认证失败。',
          ),
        ),
      );
    });

    test('does not label closed connections as unavailable network', () async {
      final client = MimoTtsApiClient(
        client: _FakeClient((_) async {
          throw http.ClientException(
            'Connection closed before full header was received',
          );
        }),
      );

      await expectLater(
        client.synthesize(
          apiKey: 'demo-key',
          text: '测试文本',
          voiceId: '冰糖',
          speedPrompt: '语速正常，段落停顿自然。',
        ),
        throwsA(
          isA<MimoTtsException>().having(
            (error) => error.message,
            'message',
            '朗读连接被中断，已缩短单段字数，请重试。',
          ),
        ),
      );
    });
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.Response response = await _handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
