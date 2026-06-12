import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../tts_playback_controller.dart';

class TtsControlSheet extends StatelessWidget {
  const TtsControlSheet({
    super.key,
    required this.palette,
    required this.state,
    required this.statusMessage,
    required this.maskedApiKey,
    required this.onStop,
    required this.onOpenSettings,
  });

  final ReaderThemePalette palette;
  final TtsPlaybackState state;
  final String? statusMessage;
  final String maskedApiKey;
  final VoidCallback onStop;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final bool canStop =
        state == TtsPlaybackState.preparing ||
        state == TtsPlaybackState.playing ||
        state == TtsPlaybackState.paused ||
        state == TtsPlaybackState.bufferingNext;
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '朗读控制',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: palette.foreground),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('朗读状态'),
                subtitle: Text(statusMessage ?? '未开始'),
                trailing: Text(
                  _stateLabel(state),
                  style: TextStyle(
                    color: palette.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('朗读与 Key 设置'),
                subtitle: Text('当前 Key：$maskedApiKey'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onOpenSettings,
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: canStop ? onStop : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('停止朗读'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _stateLabel(TtsPlaybackState state) {
    return switch (state) {
      TtsPlaybackState.idle => '未开始',
      TtsPlaybackState.needsApiKey => '需要 Key',
      TtsPlaybackState.preparing => '准备中',
      TtsPlaybackState.playing => '正在朗读',
      TtsPlaybackState.paused => '已暂停',
      TtsPlaybackState.bufferingNext => '准备下一段',
      TtsPlaybackState.completed => '已完成',
      TtsPlaybackState.error => '出错',
    };
  }
}
