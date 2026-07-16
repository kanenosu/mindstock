import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../providers.dart';
import '../theme.dart';

/// 音声入力ボタン（Whisper）。
///
/// - **タップ**で録音開始 → もう一度タップで停止して文字起こし
/// - **長押し**でも録音でき、離すと文字起こし（LINEのボイスメッセージ式）
///
/// 録音中はボタンの左に「● 0:07」の経過時間ピルが現れ、
/// 声の大きさに合わせてマイクが脈打つ。
/// 結果は [onTranscribed] に渡され、日記本文へ追記される。
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
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  double _level = 0;
  String? _path;
  String? _error;

  /// 長押しで始めたか（離した時に止めるかどうかの判定に使う）。
  bool _startedByHold = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _elapsedTimer?.cancel();
    _pulse.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start({required bool byHold}) async {
    if (_state != _RecordState.idle) return;

    // 先にAPIキーを確認して、録音してから失敗させない
    final apiKey = ref.read(openAiApiKeyProvider).valueOrNull ?? '';
    if (apiKey.isEmpty) {
      setState(() => _error = '音声入力を使うには設定画面でOpenAI APIキーを登録してください');
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) setState(() => _error = 'マイクの権限が必要です');
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
      _startedByHold = byHold;
      _elapsedSeconds = 0;
    });

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
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
    if (_state != _RecordState.recording) return;
    _elapsedTimer?.cancel();
    await _amplitudeSub?.cancel();
    final path = await _recorder.stop();
    if (path == null || _path == null) {
      setState(() => _state = _RecordState.idle);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _state = _RecordState.transcribing);

    try {
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
      unawaited(
        File(path).exists().then((exists) {
          if (exists) File(path).delete().ignore();
        }),
      );
      if (mounted) setState(() => _state = _RecordState.idle);
    }
  }

  Future<void> _cancel() async {
    _elapsedTimer?.cancel();
    await _amplitudeSub?.cancel();
    final path = await _recorder.stop();
    if (path != null && await File(path).exists()) {
      await File(path).delete();
    }
    HapticFeedback.selectionClick();
    if (mounted) setState(() => _state = _RecordState.idle);
  }

  void _onTap() {
    switch (_state) {
      case _RecordState.idle:
        _start(byHold: false);
      case _RecordState.recording:
        _stopAndTranscribe();
      case _RecordState.transcribing:
        break; // 文字起こし中は何もしない
    }
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 録音中の経過時間ピル
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0.3, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: _state == _RecordState.recording
              ? Padding(
                  key: const ValueKey('pill'),
                  padding: const EdgeInsets.only(right: 8),
                  child: _recordingPill(),
                )
              : const SizedBox.shrink(key: ValueKey('empty')),
        ),
        GestureDetector(
          onTap: _onTap,
          onLongPressStart: (_) => _start(byHold: true),
          onLongPressEnd: (_) {
            if (_state == _RecordState.recording && _startedByHold) {
              _stopAndTranscribe();
            }
          },
          onLongPressCancel: () {
            if (_state == _RecordState.recording && _startedByHold) _cancel();
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
                  color: _state == _RecordState.recording
                      ? AppColors.bear.withValues(alpha: 0.35)
                      : AppColors.ink.withValues(alpha: 0.1),
                  blurRadius: _state == _RecordState.recording ? 16 : 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(child: _icon()),
          ),
        ),
      ],
    );
  }

  Widget _recordingPill() {
    final m = _elapsedSeconds ~/ 60;
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.bear,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$m:$s',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'タップで完了',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
        ],
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
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.ink,
          ),
        );
    }
  }
}
