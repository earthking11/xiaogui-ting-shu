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
  bool _saving = false;
  bool _testing = false;
  String? _testResult;

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
                  '阅读设置',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: palette.foreground),
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: '主题', color: palette.foreground),
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
                        selected: item.id == widget.readerSettings.themeId,
                        onSelected: (_) => widget.onReaderSettingsChanged(
                          widget.readerSettings.copyWith(themeId: item.id),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: '字号', color: palette.foreground),
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
                        selected:
                            widget.readerSettings.fontSize == size.toDouble(),
                        onSelected: (_) => widget.onReaderSettingsChanged(
                          widget.readerSettings.copyWith(
                            fontSize: size.toDouble(),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: '行距', color: palette.foreground),
                Slider(
                  min: 1.45,
                  max: 2.05,
                  divisions: 12,
                  value: widget.readerSettings.lineHeight,
                  label: widget.readerSettings.lineHeight.toStringAsFixed(2),
                  activeColor: palette.accent,
                  inactiveColor: palette.border,
                  onChanged: (value) => widget.onReaderSettingsChanged(
                    widget.readerSettings.copyWith(lineHeight: value),
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: '音色', color: palette.foreground),
                DropdownButtonFormField<String>(
                  initialValue: widget.ttsSettings.voiceId,
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
                    widget.onTtsSettingsChanged(
                      widget.ttsSettings.copyWith(
                        voiceId: voice.id,
                        voiceName: voice.name,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                _SectionTitle(title: '语速', color: palette.foreground),
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
                            widget.ttsSettings.playbackSpeed ==
                            option.playbackSpeed,
                        onSelected: (_) => widget.onTtsSettingsChanged(
                          widget.ttsSettings.copyWith(
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
                    hintText: widget.maskedApiKey == '未填写'
                        ? '填写 MiMo API Key'
                        : '当前：${widget.maskedApiKey}',
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
                                  return;
                                }
                                setState(() => _saving = true);
                                await widget.onSaveApiKey(value);
                                if (mounted) {
                                  _apiKeyController.clear();
                                  setState(() => _saving = false);
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
                                setState(() => _saving = true);
                                await widget.onClearApiKey();
                                if (mounted) {
                                  _apiKeyController.clear();
                                  setState(() => _saving = false);
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
                              _testResult = null;
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
                              _testResult = result;
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
                if (_testResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.background.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: palette.foreground,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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
