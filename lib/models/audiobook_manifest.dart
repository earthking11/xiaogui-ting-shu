enum AudiobookJobStatus { pending, generating, paused, completed, error }

enum AudiobookClipStatus { pending, generating, done, failed }

class AudiobookClip {
  const AudiobookClip({
    required this.sentenceIndex,
    required this.paragraphIndex,
    required this.text,
    required this.status,
    this.audioPath,
    this.errorMessage,
    this.updatedAt,
  });

  final int sentenceIndex;
  final int paragraphIndex;
  final String text;
  final AudiobookClipStatus status;
  final String? audioPath;
  final String? errorMessage;
  final DateTime? updatedAt;

  AudiobookClip copyWith({
    AudiobookClipStatus? status,
    String? audioPath,
    String? errorMessage,
    DateTime? updatedAt,
    bool clearAudioPath = false,
    bool clearError = false,
  }) {
    return AudiobookClip(
      sentenceIndex: sentenceIndex,
      paragraphIndex: paragraphIndex,
      text: text,
      status: status ?? this.status,
      audioPath: clearAudioPath ? null : audioPath ?? this.audioPath,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sentenceIndex': sentenceIndex,
      'paragraphIndex': paragraphIndex,
      'text': text,
      'status': status.name,
      'audioPath': audioPath,
      'errorMessage': errorMessage,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory AudiobookClip.fromJson(Map<String, dynamic> json) {
    return AudiobookClip(
      sentenceIndex: json['sentenceIndex'] as int? ?? 0,
      paragraphIndex: json['paragraphIndex'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      status: _clipStatusFromName(json['status'] as String?),
      audioPath: json['audioPath'] as String?,
      errorMessage: json['errorMessage'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

class AudiobookManifest {
  const AudiobookManifest({
    required this.bookId,
    required this.planId,
    required this.textVersionHash,
    required this.voiceId,
    required this.voiceName,
    required this.playbackSpeed,
    required this.speedPrompt,
    required this.audioFormat,
    required this.status,
    required this.clips,
    required this.createdAt,
    required this.updatedAt,
    this.statusMessage,
  });

  final String bookId;
  final String planId;
  final String textVersionHash;
  final String voiceId;
  final String voiceName;
  final double playbackSpeed;
  final String speedPrompt;
  final String audioFormat;
  final AudiobookJobStatus status;
  final List<AudiobookClip> clips;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? statusMessage;

  int get totalSentenceCount => clips.length;
  int get generatedSentenceCount =>
      clips.where((clip) => clip.status == AudiobookClipStatus.done).length;
  int get failedSentenceCount =>
      clips.where((clip) => clip.status == AudiobookClipStatus.failed).length;
  bool get hasPlayableAudio => generatedSentenceCount > 0;
  double get progress {
    if (clips.isEmpty) {
      return 0;
    }
    return generatedSentenceCount / clips.length;
  }

  AudiobookManifest copyWith({
    AudiobookJobStatus? status,
    List<AudiobookClip>? clips,
    DateTime? updatedAt,
    String? statusMessage,
    bool clearStatusMessage = false,
  }) {
    return AudiobookManifest(
      bookId: bookId,
      planId: planId,
      textVersionHash: textVersionHash,
      voiceId: voiceId,
      voiceName: voiceName,
      playbackSpeed: playbackSpeed,
      speedPrompt: speedPrompt,
      audioFormat: audioFormat,
      status: status ?? this.status,
      clips: clips ?? this.clips,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      statusMessage: clearStatusMessage
          ? null
          : statusMessage ?? this.statusMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bookId': bookId,
      'planId': planId,
      'textVersionHash': textVersionHash,
      'voiceId': voiceId,
      'voiceName': voiceName,
      'playbackSpeed': playbackSpeed,
      'speedPrompt': speedPrompt,
      'audioFormat': audioFormat,
      'status': status.name,
      'statusMessage': statusMessage,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'clips': clips.map((clip) => clip.toJson()).toList(),
    };
  }

  factory AudiobookManifest.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawClips = json['clips'] as List<dynamic>? ?? const [];
    return AudiobookManifest(
      bookId: json['bookId'] as String? ?? '',
      planId: json['planId'] as String? ?? '',
      textVersionHash: json['textVersionHash'] as String? ?? '',
      voiceId: json['voiceId'] as String? ?? '',
      voiceName: json['voiceName'] as String? ?? '',
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      speedPrompt: json['speedPrompt'] as String? ?? '',
      audioFormat: json['audioFormat'] as String? ?? 'mp3',
      status: _jobStatusFromName(json['status'] as String?),
      statusMessage: json['statusMessage'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      clips: rawClips
          .whereType<Map>()
          .map(
            (item) => AudiobookClip.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
    );
  }
}

class AudiobookSummary {
  const AudiobookSummary({
    required this.bookId,
    required this.status,
    required this.generatedSentenceCount,
    required this.totalSentenceCount,
    required this.failedSentenceCount,
    required this.audioBytes,
    required this.voiceName,
    required this.playbackSpeed,
    required this.updatedAt,
  });

  final String bookId;
  final AudiobookJobStatus status;
  final int generatedSentenceCount;
  final int totalSentenceCount;
  final int failedSentenceCount;
  final int audioBytes;
  final String voiceName;
  final double playbackSpeed;
  final DateTime updatedAt;

  double get progress {
    if (totalSentenceCount == 0) {
      return 0;
    }
    return generatedSentenceCount / totalSentenceCount;
  }
}

AudiobookJobStatus _jobStatusFromName(String? name) {
  return AudiobookJobStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => AudiobookJobStatus.pending,
  );
}

AudiobookClipStatus _clipStatusFromName(String? name) {
  return AudiobookClipStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => AudiobookClipStatus.pending,
  );
}
