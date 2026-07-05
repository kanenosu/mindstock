import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../providers.dart';
import '../theme.dart';

/// 音声入力ボタン。長押しで録音開始、離すとWhisperで文字起こしして
/// [onTranscribed] に結果を渡す。タップだけの誤操作を避けるため、
/// ホールド方式（LINEのボイスメッセージと同じ操作感）にしている。
class VoiceInputButton extends ConsumerStatefulWidget {
  final ValueChanged<String> onTranscribed;

  const VoiceInputButton({super.key, required this.onTranscribed});

  @override
  ConsumerState<VoiceInputButton> createState() => _VoiceInputButtonState();
}

enum _RecordState { idle, recording, transcribing }

class _VoiceInputButtonState extends ConsumerState<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  _RecordState _state = _RecordState.idle;
  StreamSubscription<Amplitude>? _amplitudeSub;
  double _level = 0;
  String? _path;
  String? _error;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _pulse.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        setState(() => _error = 'マイクの権限が必要です');
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/mindstock_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(), path: path);
    HapticFeedback.mediumImpact();
    setState(() {
      _state = _RecordState.recording;
      _path = path;
      _error = null;
    });

    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amp) {
          // dBFS(-45〜0程度)を0〜1へ大まかに正規化して波形の強弱に使う
          final normalized = ((amp.current + 45) / 45).clamp(0.0, 1.0);
          if (mounted) setState(() => _level = normalized);
        });
  }

  Future<void> _stopAndTranscribe() async {
    await _amplitudeSub?.cancel();
    final path = await _recorder.stop();
    if (path == null || _path == null) {
      setState(() => _state = _RecordState.idle);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _state = _RecordState.transcribing);

    try {
      final apiKey = ref.read(openAiApiKeyProvider).valueOrNull ?? '';
      if (apiKey.isEmpty) {
        throw StateError(
          '音声入力を使うには設定画面でOpenAI APIキーを登録してください',
        );
      }
      final service = ref.read(transcriptionServiceProvider);
      final text = await service.transcribe(path);
      if (text.isEmpty) {
        throw StateError('音声を認識できませんでした。もう一度試してください');
      }
      widget.onTranscribed(text);
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StateError ? e.message : e.toString());
      }
    } finally {
      unawaited(File(path).exists().then((exists) {
        if (exists) File(path).delete().ignore();
      }));
      if (mounted) setState(() => _state = _RecordState.idle);
    }
  }

  Future<void> _cancel() async {
    await _amplitudeSub?.cancel();
    final path = await _recorder.stop();
    if (path != null && await File(path).exists()) {
      await File(path).delete();
    }
    HapticFeedback.selectionClick();
    setState(() => _state = _RecordState.idle);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_error!)));
        setState(() => _error = null);
      });
    }

    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) {
        if (_state == _RecordState.recording) _stopAndTranscribe();
      },
      onLongPressCancel: () {
        if (_state == _RecordState.recording) _cancel();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: _state == _RecordState.recording
              ? AppColors.bear
              : AppColors.card,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(child: _icon()),
      ),
    );
  }

  Widget _icon() {
    switch (_state) {
      case _RecordState.idle:
        return const Icon(Icons.mic_none_rounded, color: AppColors.ink);
      case _RecordState.recording:
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final scale = 1.0 + _level * 0.3 + _pulse.value * 0.08;
            return Transform.scale(
              scale: scale,
              child: const Icon(Icons.mic_rounded, color: Colors.white),
            );
          },
        );
      case _RecordState.transcribing:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink),
        );
    }
  }
}
