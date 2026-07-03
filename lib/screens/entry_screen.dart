import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../logic/chart_calculator.dart';
import '../providers.dart';

/// 日記入力画面（仕様書 §7-1）。
///
/// コア体験: 書く → 送信 → AIが即採点 → その日のローソク足に自動反映。
/// 確認画面は挟まない。気分スライダーは「軽めの日」用（任意）。
class EntryScreen extends ConsumerStatefulWidget {
  const EntryScreen({super.key});

  @override
  ConsumerState<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends ConsumerState<EntryScreen> {
  final _controller = TextEditingController();
  double? _mood;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // 今日すでに書いていれば続きから編集できるようにする
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = ChartCalculator.dateKey(DateTime.now());
      final entry = ref.read(entriesProvider).valueOrNull?[key];
      if (entry != null && _controller.text.isEmpty) {
        _controller.text = entry.text;
        setState(() => _mood = entry.moodScore);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _mood == null) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(entriesProvider.notifier)
          .submitDiary(date: DateTime.now(), text: text, moodScore: _mood);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('記録しました。チャートに反映済みです')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('M月d日 (E)', 'ja').format(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text(today)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '今日のことを、ただ書くだけ。',
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 16, height: 1.7),
                ),
              ),
              const SizedBox(height: 8),
              _MoodSlider(
                value: _mood,
                onChanged: (v) => setState(() => _mood = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
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

/// 気分スライダー（軽めの日用の入力階層、仕様書 §2）。
class _MoodSlider extends StatelessWidget {
  final double? value;
  final ValueChanged<double?> onChanged;

  const _MoodSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('今日の気分', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            if (value != null)
              TextButton(
                onPressed: () => onChanged(null),
                child: const Text('クリア'),
              ),
          ],
        ),
        Row(
          children: [
            const Text('😞'),
            Expanded(
              child: Slider(
                value: value ?? 5,
                min: 0,
                max: 10,
                divisions: 20,
                label: value?.toStringAsFixed(1),
                onChanged: onChanged,
              ),
            ),
            const Text('😊'),
          ],
        ),
      ],
    );
  }
}
