import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/constants.dart';
import '../../../models/reader_settings.dart';
import '../../../models/tts_settings.dart';

class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.palette,
    required this.readerSettings,
    required this.ttsSettings,
    required this.maskedApiKey,
    required this.onReaderSettingsChanged,
    required this.onTtsSettingsChanged,
    required this.onSaveApiKey,
    required this.onClearApiKey,
    required this.onTestApiKey,
  });

  final ReaderThemePalette palette;
  final ReaderSettings readerSettings;
  final TtsSettings ttsSettings;
  final String maskedApiKey;
  final ValueChanged<ReaderSettings> onReaderSettingsChanged;
  final ValueChanged<TtsSettings> onTtsSettingsChanged;
  final Future<void> Function(String apiKey) onSaveApiKey;
  final Future<void> Function() onClearApiKey;
  final Future<String> Function(String draftApiKey) onTestApiKey;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late final TextEditingController _apiKeyController = TextEditingController();
  late ReaderSettings _readerSettings;
  late TtsSettings _ttsSettings;
  late String _maskedApiKey;
  bool _saving = false;
  bool _testing = false;
  String? _apiFeedback;
  bool _apiFeedbackSucceeded = false;

  @override
  void initState() {
    super.initState();
    _readerSettings = widget.readerSettings;
    _ttsSettings = widget.ttsSettings;
    _maskedApiKey = widget.maskedApiKey;
  }

  @override
  void didUpdateWidget(covariant ReaderSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readerSettings != widget.readerSettings) {
      _readerSettings = widget.readerSettings;
    }
    if (oldWidget.ttsSettings != widget.ttsSettings) {
      _ttsSettings = widget.ttsSettings;
    }
    if (oldWidget.maskedApiKey != widget.maskedApiKey) {
      _maskedApiKey = widget.maskedApiKey;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final TextStyle chipTextStyle = TextStyle(
      color: palette.foreground,
      fontWeight: FontWeight.w600,
    );
    final BorderSide controlBorder = BorderSide(color: palette.border);
    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderSide: controlBorder,
    );
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: palette.foreground),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '阅读及 TTS 设置',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: palette.foreground),
                ),
                const SizedBox(height: 6),
                Text(
                  '外观、朗读声音和 API Key 都在这里调整。',
                  style: TextStyle(
                    color: palette.secondaryText,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: '阅读外观', color: palette.foreground),
                _SubsectionLabel(text: '主题', color: palette.secondaryText),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in AppTheme.palettes)
                      ChoiceChip(
                        label: Text(item.name),
                        labelStyle: chipTextStyle,
                        selectedColor: palette.accent.withValues(alpha: 0.22),
                        backgroundColor: palette.background.withValues(
                          alpha: 0.70,
                        ),
                        side: controlBorder,
                        checkmarkColor: palette.accent,
                        selected: item.id == _readerSettings.themeId,
                        onSelected: (_) => _applyReaderSettings(
                          _readerSettings.copyWith(themeId: item.id),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _SubsectionLabel(text: '字号', color: palette.secondaryText),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final size in const [14, 16, 18, 20, 22, 24, 26])
                      ChoiceChip(
                        label: Text('$size'),
                        labelStyle: chipTextStyle,
                        selectedColor: palette.accent.withValues(alpha: 0.22),
                        backgroundColor: palette.background.withValues(
                          alpha: 0.70,
                        ),
                        side: controlBorder,
                        checkmarkColor: palette.accent,
                        selected: _readerSettings.fontSize == size.toDouble(),
                        onSelected: (_) => _applyReaderSettings(
                          _readerSettings.copyWith(fontSize: size.toDouble()),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _SubsectionLabel(text: '行距', color: palette.secondaryText),
                Slider(
                  min: 1.45,
                  max: 2.05,
                  divisions: 12,
                  value: _readerSettings.lineHeight,
                  label: _readerSettings.lineHeight.toStringAsFixed(2),
                  activeColor: palette.accent,
                  inactiveColor: palette.border,
                  onChanged: (value) => _applyReaderSettings(
                    _readerSettings.copyWith(lineHeight: value),
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: '朗读设置', color: palette.foreground),
                _SubsectionLabel(text: '音色', color: palette.secondaryText),
                DropdownButtonFormField<String>(
                  initialValue: _ttsSettings.voiceId,
                  dropdownColor: palette.card,
                  style: TextStyle(color: palette.foreground, fontSize: 15),
                  decoration: InputDecoration(
                    border: inputBorder,
                    enabledBorder: inputBorder,
                    focusedBorder: inputBorder.copyWith(
                      borderSide: BorderSide(color: palette.accent, width: 1.4),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  items: [
                    for (final voice in kVoiceOptions)
                      DropdownMenuItem<String>(
                        value: voice.id,
                        child: Text(
                          '${voice.name} · ${voice.language} ${voice.gender}',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    final voice = voiceOptionFor(value);
                    _applyTtsSettings(
                      _ttsSettings.copyWith(
                        voiceId: voice.id,
                        voiceName: voice.name,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _SubsectionLabel(text: '语速', color: palette.secondaryText),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in kPlaybackSpeedOptions)
                      ChoiceChip(
                        label: Text(option.label),
                        labelStyle: chipTextStyle,
                        selectedColor: palette.accent.withValues(alpha: 0.22),
                        backgroundColor: palette.background.withValues(
                          alpha: 0.70,
                        ),
                        side: controlBorder,
                        checkmarkColor: palette.accent,
                        selected:
                            _ttsSettings.playbackSpeed == option.playbackSpeed,
                        onSelected: (_) => _applyTtsSettings(
                          _ttsSettings.copyWith(
                            playbackSpeed: option.playbackSpeed,
                            speedPrompt: option.prompt,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: 'MiMo API Key', color: palette.foreground),
                TextField(
                  controller: _apiKeyController,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  style: TextStyle(color: palette.foreground),
                  decoration: InputDecoration(
                    hintText: _maskedApiKey == '未填写'
                        ? '填写 MiMo API Key'
                        : '当前：$_maskedApiKey',
                    hintStyle: TextStyle(color: palette.secondaryText),
                    border: inputBorder,
                    enabledBorder: inputBorder,
                    focusedBorder: inputBorder.copyWith(
                      borderSide: BorderSide(color: palette.accent, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Key 只保存在本机，用于调用小米 MiMo TTS。',
                  style: TextStyle(
                    color: palette.foreground.withValues(alpha: 0.72),
                    fontSize: 13,
                  ),
                ),
                if (_apiFeedback != null) ...[
                  const SizedBox(height: 10),
                  _ApiFeedbackCard(
                    palette: palette,
                    message: _apiFeedback!,
                    succeeded: _apiFeedbackSucceeded,
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving || _testing
                            ? null
                            : () async {
                                final String value = _apiKeyController.text
                                    .trim();
                                if (value.isEmpty) {
                                  setState(() {
                                    _apiFeedback = '请先填写 API Key。';
                                    _apiFeedbackSucceeded = false;
                                  });
                                  return;
                                }
                                setState(() {
                                  _saving = true;
                                  _apiFeedback = null;
                                });
                                await widget.onSaveApiKey(value);
                                if (mounted) {
                                  _apiKeyController.clear();
                                  setState(() {
                                    _saving = false;
                                    _maskedApiKey = _maskApiKey(value);
                                    _apiFeedback = 'API Key 已保存。';
                                    _apiFeedbackSucceeded = true;
                                  });
                                }
                              },
                        child: Text(_saving ? '保存中...' : '保存 Key'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving || _testing
                            ? null
                            : () async {
                                setState(() {
                                  _saving = true;
                                  _apiFeedback = null;
                                });
                                await widget.onClearApiKey();
                                if (mounted) {
                                  _apiKeyController.clear();
                                  setState(() {
                                    _saving = false;
                                    _maskedApiKey = '未填写';
                                    _apiFeedback = 'API Key 已清除。';
                                    _apiFeedbackSucceeded = true;
                                  });
                                }
                              },
                        child: const Text('清除 Key'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saving || _testing
                        ? null
                        : () async {
                            setState(() {
                              _testing = true;
                              _apiFeedback = null;
                            });
                            String result;
                            try {
                              result = await widget.onTestApiKey(
                                _apiKeyController.text,
                              );
                            } on Exception catch (error) {
                              result = '测试异常：${error.runtimeType}。';
                            }
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _testing = false;
                              _apiFeedback = result;
                              _apiFeedbackSucceeded = result.startsWith(
                                '连通性正常',
                              );
                            });
                          },
                    icon: _testing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.accent,
                            ),
                          )
                        : const Icon(Icons.network_check_rounded),
                    label: Text(_testing ? '正在测试连通性...' : '测试 API 连通性'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _applyReaderSettings(ReaderSettings value) {
    setState(() => _readerSettings = value);
    widget.onReaderSettingsChanged(value);
  }

  void _applyTtsSettings(TtsSettings value) {
    setState(() => _ttsSettings = value);
    widget.onTtsSettingsChanged(value);
  }

  String _maskApiKey(String apiKey) {
    final String value = apiKey.trim();
    if (value.isEmpty) {
      return '未填写';
    }
    if (value.length <= 4) {
      return '*' * value.length;
    }
    return '${'*' * (value.length - 4)}${value.substring(value.length - 4)}';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ApiFeedbackCard extends StatelessWidget {
  const _ApiFeedbackCard({
    required this.palette,
    required this.message,
    required this.succeeded,
  });

  final ReaderThemePalette palette;
  final String message;
  final bool succeeded;

  @override
  Widget build(BuildContext context) {
    final Color signalColor = succeeded ? palette.accent : Colors.redAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: signalColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: signalColor.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            succeeded
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            size: 18,
            color: signalColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.foreground,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubsectionLabel extends StatelessWidget {
  const _SubsectionLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
