import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../tts_playback_controller.dart';

class TtsStatusBar extends StatelessWidget {
  const TtsStatusBar({
    super.key,
    required this.palette,
    required this.controller,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onStop,
  });

  final ReaderThemePalette palette;
  final TtsPlaybackController controller;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final TtsPlaybackState state = controller.state;
    if (state == TtsPlaybackState.idle) {
      return const SizedBox.shrink();
    }

    final IconData icon = switch (state) {
      TtsPlaybackState.playing => Icons.graphic_eq_rounded,
      TtsPlaybackState.paused => Icons.pause_circle_outline_rounded,
      TtsPlaybackState.completed => Icons.check_circle_outline_rounded,
      TtsPlaybackState.error => Icons.error_outline_rounded,
      TtsPlaybackState.bufferingNext ||
      TtsPlaybackState.preparing => Icons.hourglass_top_rounded,
      TtsPlaybackState.needsApiKey => Icons.vpn_key_outlined,
      TtsPlaybackState.idle => Icons.graphic_eq_rounded,
    };

    final bool canToggle =
        state == TtsPlaybackState.playing ||
        state == TtsPlaybackState.paused ||
        state == TtsPlaybackState.error ||
        state == TtsPlaybackState.completed ||
        state == TtsPlaybackState.needsApiKey;
    final double progress = controller.playbackProgress;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: palette.toolbar,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: palette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.statusMessage ?? '准备中',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      controller.currentPreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.secondaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: canToggle ? onPrimary : null,
                icon: Icon(
                  state == TtsPlaybackState.playing ||
                          state == TtsPlaybackState.bufferingNext
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                onPressed:
                    state == TtsPlaybackState.preparing ||
                        state == TtsPlaybackState.playing ||
                        state == TtsPlaybackState.paused ||
                        state == TtsPlaybackState.bufferingNext
                    ? onStop
                    : null,
                icon: const Icon(Icons.stop_rounded),
                color: palette.foreground,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PlaybackProgressLine(palette: palette, progress: progress),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _formatDuration(controller.position),
                style: TextStyle(
                  color: palette.secondaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                controller.nextStatusLabel,
                style: TextStyle(
                  color: palette.foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                _formatDuration(controller.duration),
                style: TextStyle(
                  color: palette.secondaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PlaybackProgressLine extends StatelessWidget {
  const _PlaybackProgressLine({required this.palette, required this.progress});

  final ReaderThemePalette palette;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double dotLeft = (width * progress).clamp(0, width);
        return SizedBox(
          height: 14,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Positioned(
                left: dotLeft - 6,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.card, width: 2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
