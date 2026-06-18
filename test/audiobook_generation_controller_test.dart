import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_tts_reader/features/audiobook/audiobook_generation_controller.dart';
import 'package:novel_tts_reader/models/audiobook_manifest.dart';
import 'package:novel_tts_reader/services/audiobook_repository.dart';
import 'package:novel_tts_reader/services/mimo_tts_api_client.dart';
import 'package:novel_tts_reader/services/secure_key_store.dart';

void main() {
  group('AudiobookGenerationController', () {
    test('retry resets stuck generating and failed clips', () async {
      final repository = _MemoryAudiobookRepository();
      final apiClient = _ImmediateApiClient();
      final controller = AudiobookGenerationController(
        repository: repository,
        apiClient: apiClient,
        keyStore: const _FakeKeyStore('valid-key'),
        manifest: _manifest([
          AudiobookClipStatus.generating,
          AudiobookClipStatus.failed,
          AudiobookClipStatus.done,
        ]),
      );

      await controller.start(retryFailed: true);

      expect(apiClient.requestedTexts, ['句子 1', '句子 2']);
      expect(
        controller.manifest.clips.map((clip) => clip.status),
        everyElement(AudiobookClipStatus.done),
      );
      expect(controller.manifest.status, AudiobookJobStatus.completed);
    });

    test(
      'deletePlan waits for the active generation run before reset',
      () async {
        final repository = _MemoryAudiobookRepository();
        final apiClient = _BlockingApiClient(expectedCalls: 2);
        final controller = AudiobookGenerationController(
          repository: repository,
          apiClient: apiClient,
          keyStore: const _FakeKeyStore('valid-key'),
          manifest: _manifest([
            AudiobookClipStatus.pending,
            AudiobookClipStatus.pending,
          ]),
        );

        final Future<void> startFuture = controller.start();
        await apiClient.waitForExpectedCalls();

        final Future<void> deleteFuture = controller.deletePlan();
        await Future<void>.delayed(Duration.zero);

        expect(repository.deletePlanCalls, 0);

        apiClient.completeAll();
        await deleteFuture;
        await startFuture;

        expect(repository.deletePlanCalls, 1);
        expect(controller.manifest.status, AudiobookJobStatus.pending);
        expect(
          controller.manifest.clips.map((clip) => clip.status),
          everyElement(AudiobookClipStatus.pending),
        );
        expect(
          controller.manifest.clips.map((clip) => clip.audioPath),
          everyElement(isNull),
        );
      },
    );

    test('pause is a no-op when no generation run is active', () async {
      final repository = _MemoryAudiobookRepository();
      final controller = AudiobookGenerationController(
        repository: repository,
        apiClient: _ImmediateApiClient(),
        keyStore: const _FakeKeyStore('valid-key'),
        manifest: _manifest([
          AudiobookClipStatus.done,
        ], status: AudiobookJobStatus.completed),
      );

      await controller.pause();

      expect(controller.manifest.status, AudiobookJobStatus.completed);
      expect(repository.savedManifests, isEmpty);
    });
  });
}

AudiobookManifest _manifest(
  List<AudiobookClipStatus> statuses, {
  AudiobookJobStatus status = AudiobookJobStatus.pending,
}) {
  final DateTime now = DateTime(2026, 6, 17, 12);
  return AudiobookManifest(
    bookId: 'book-1',
    planId: 'plan-1',
    textVersionHash: 'hash',
    voiceId: 'voice',
    voiceName: 'voice',
    playbackSpeed: 1,
    speedPrompt: '自然朗读',
    audioFormat: 'mp3',
    status: status,
    clips: [
      for (int i = 0; i < statuses.length; i++)
        AudiobookClip(
          sentenceIndex: i,
          paragraphIndex: 0,
          text: '句子 ${i + 1}',
          status: statuses[i],
          audioPath: statuses[i] == AudiobookClipStatus.done
              ? '/tmp/sentence_$i.mp3'
              : null,
          errorMessage: statuses[i] == AudiobookClipStatus.failed ? '失败' : null,
          updatedAt: now,
        ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

class _MemoryAudiobookRepository extends AudiobookRepository {
  int deletePlanCalls = 0;
  final List<AudiobookManifest> savedManifests = [];

  @override
  Future<void> saveManifest(AudiobookManifest manifest) async {
    savedManifests.add(manifest);
  }

  @override
  Future<String> saveClipAudio({
    required AudiobookManifest manifest,
    required int sentenceIndex,
    required Uint8List bytes,
  }) async {
    return '/tmp/${manifest.planId}_$sentenceIndex.${manifest.audioFormat}';
  }

  @override
  Future<void> deletePlan(AudiobookManifest manifest) async {
    deletePlanCalls += 1;
  }
}

class _ImmediateApiClient extends MimoTtsApiClient {
  _ImmediateApiClient() : super(endpoint: Uri.parse('https://example.test'));

  final List<String> requestedTexts = [];

  @override
  Future<Uint8List> synthesize({
    required String apiKey,
    required String text,
    required String voiceId,
    required String speedPrompt,
    String audioFormat = 'mp3',
  }) async {
    requestedTexts.add(text);
    return Uint8List.fromList([1, 2, 3]);
  }
}

class _BlockingApiClient extends MimoTtsApiClient {
  _BlockingApiClient({required this.expectedCalls})
    : super(endpoint: Uri.parse('https://example.test'));

  final int expectedCalls;
  final List<Completer<Uint8List>> _requests = [];
  final Completer<void> _expectedCallsStarted = Completer<void>();

  Future<void> waitForExpectedCalls() {
    if (_requests.length >= expectedCalls) {
      return Future<void>.value();
    }
    return _expectedCallsStarted.future.timeout(const Duration(seconds: 2));
  }

  void completeAll() {
    for (final Completer<Uint8List> request in _requests) {
      if (!request.isCompleted) {
        request.complete(Uint8List.fromList([1, 2, 3]));
      }
    }
  }

  @override
  Future<Uint8List> synthesize({
    required String apiKey,
    required String text,
    required String voiceId,
    required String speedPrompt,
    String audioFormat = 'mp3',
  }) {
    final completer = Completer<Uint8List>();
    _requests.add(completer);
    if (_requests.length >= expectedCalls &&
        !_expectedCallsStarted.isCompleted) {
      _expectedCallsStarted.complete();
    }
    return completer.future;
  }
}

class _FakeKeyStore implements SecureKeyStore {
  const _FakeKeyStore(this.apiKey);

  final String? apiKey;

  @override
  Future<void> clearApiKey() async {}

  @override
  String mask(String? apiKey) => apiKey == null ? '未填写' : '****';

  @override
  Future<String?> readApiKey() async => apiKey;

  @override
  Future<void> saveApiKey(String apiKey) async {}
}
