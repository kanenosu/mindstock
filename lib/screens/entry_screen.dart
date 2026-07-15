import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../logic/chart_calculator.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/diary_calendar.dart';
import '../widgets/voice_input_button.dart';

/// 日記入力画面（仕様書 §7-1）。
///
/// コア体験: 書く → 送信 → AIが即採点 → その日のローソク足に自動反映。
/// 確認画面は挟まない。
///
/// 気分は絵文字を1つ選ぶだけ（軽めの日用の入力階層、仕様書 §2）。
/// 文章を書いた日は気分は使わず、採点はAIに任せる —
/// なので本文を書き始めると絵文字ピッカーは畳まれる。
class EntryScreen extends ConsumerStatefulWidget {
  final DateTime? initialDate;

  const EntryScreen({super.key, this.initialDate});

  @override
  ConsumerState<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends ConsumerState<EntryScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late DateTime _date;
  double? _mood;
  bool _submitting = false;

  bool get _hasText => _controller.text.trim().isNotEmpty;
  bool get _canSubmit => _hasText || _mood != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final d = widget.initialDate ?? now;
    _date = DateTime(d.year, d.month, d.day);
    _loadEntryFor(_date);
    // 書き始めたら（フォーカスが入ったら）カレンダーを畳んで本文に集中させる
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 選択した日付にすでに記録があれば続きから編集できるようにする。
  void _loadEntryFor(DateTime date) {
    final key = ChartCalculator.dateKey(date);
    final entry = ref.read(entriesProvider).valueOrNull?[key];
    _controller.text = entry?.text ?? '';
    setState(() => _mood = entry?.moodScore);
  }

  void _selectDate(DateTime picked) {
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    _loadEntryFor(_date);
  }

  /// Whisperの文字起こし結果を本文に追記する。
  /// 既に何か書いてあれば改行してから続ける。
  void _appendTranscribed(String text) {
    final current = _controller.text;
    final needsBreak = current.isNotEmpty && !current.endsWith('\n');
    final updated = current.isEmpty
        ? text
        : '$current${needsBreak ? '\n' : ''}$text';
    setState(() {
      _controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: updated.length),
      );
    });
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      await ref.read(entriesProvider.notifier).submitDiary(
        date: _date,
        text: text,
        // 文章を書いた日は気分は使わない — 採点はAIに任せる
        moodScore: text.isNotEmpty ? null : _mood,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      FocusManager.instance.primaryFocus?.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('記録しました。チャートに反映済みです')),
      );
      Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = DateUtils.isSameDay(_date, today);
    final label = isToday
        ? '今日の日記'
        : DateFormat('M月d日 (E) の日記', 'ja').format(_date);
    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(label, key: ValueKey(label)),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // カレンダーから日付を選んですぐ移動できる（緑● / 赤● = その日の記録）。
              // 本文入力中（キーボード表示中）は畳んで、狭い画面で本文と
              // 重ならないようにする。フォーカスを外すとまた開く。
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _focusNode.hasFocus
                    ? const SizedBox(width: double.infinity)
                    : DiaryCalendar(selected: _date, onSelect: _selectDate),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        onChanged: (_) => setState(() {}),
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: const InputDecoration(
                          hintText: '今日のことを、ただ書くだけ。\n（マイクをタップして話しても書ける）',
                          border: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.only(
                            bottom: 64,
                            right: 8,
                          ),
                        ),
                        style: const TextStyle(fontSize: 16, height: 1.7),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 4,
                      child: VoiceInputButton(
                        onTranscribed: _appendTranscribed,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _hasText
                    ? Padding(
                        key: const ValueKey('note'),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '文章を書いた日は、採点はAIにおまかせ。',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.inkSoft),
                        ),
                      )
                    : MoodEmojiPicker(
                        key: const ValueKey('picker'),
                        value: _mood,
                        onChanged: (v) => setState(() => _mood = v),
                      ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: (_submitting || !_canSubmit) ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_submitting ? '解析中…' : '記録する'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 気分の絵文字ピッカー。タップひとつで完了する最軽量の入力（仕様書 §2 軽め）。
/// もう一度タップで解除。値は従来の気分スコア(0〜10)にマッピングして保存する。
class MoodEmojiPicker extends StatelessWidget {
  final double? value;
  final ValueChanged<double?> onChanged;

  const MoodEmojiPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const moods = [
    ('😢', 1.0),
    ('😕', 3.0),
    ('😐', 5.0),
    ('🙂', 7.0),
    ('😄', 9.0),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '書かない日は、気分をひとつだけ。',
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: AppColors.inkSoft),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final (emoji, score) in moods)
              _MoodButton(
                emoji: emoji,
                selected: value == score,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(value == score ? null : score);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _MoodButton extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _MoodButton({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: selected ? AppColors.card : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.accent : Colors.transparent,
          width: 2,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: AnimatedScale(
              scale: selected ? 1.25 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
        ),
      ),
    );
  }
}
