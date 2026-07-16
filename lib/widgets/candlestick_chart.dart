import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/models.dart';
import '../theme.dart';

/// チャートの描画スタイル。
enum ChartStyle {
  /// ローソク足（週足用）。OHLCをフルに表現する。
  candle,

  /// 点＋ライン（日足用）。その日の終値をただの点として描く。
  line,
}

/// メインチャート（仕様書 §5）。
///
/// - [ChartStyle.candle]: 緑 = 陽線（トータルでプラス）、赤 = 陰線
/// - [ChartStyle.line]: 終値の点を線で結ぶシンプルな表示
/// - ピンチズーム・横スクロール対応（仕様書 §6 (2)）
/// - 移動平均線の重ね描き
/// - タップすると [onSelect] でその期間を通知（振り返り導線）
class CandlestickChart extends StatefulWidget {
  final List<Candle> candles;
  final List<double?> movingAverage;
  final ChartStyle style;
  final void Function(Candle candle)? onSelect;

  const CandlestickChart({
    super.key,
    required this.candles,
    this.movingAverage = const [],
    this.style = ChartStyle.candle,
    this.onSelect,
  });

  @override
  State<CandlestickChart> createState() => _CandlestickChartState();
}

class _CandlestickChartState extends State<CandlestickChart>
    with SingleTickerProviderStateMixin {
  /// 1本あたりの横幅(px)。ピンチズームで変化する。
  double _candleWidth = 14;

  /// 右端から何本分スクロールして戻っているか。0 = 最新を表示。
  double _scrollOffset = 0;

  double _scaleStartWidth = 14;

  /// ピンチ開始時、焦点位置が右端から何本目だったか。
  /// ズーム中もこの足が指の下に留まるようにオフセットを補正する。
  double _scaleStartFocalFromRight = 0;
  int? _selectedIndex;

  /// 慣性スクロール（指を離した後もスッと滑る）用。
  late final AnimationController _fling = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onFlingTick);

  static const _minWidth = 4.0;
  static const _maxWidth = 40.0;

  double get _maxOffset => max(0, widget.candles.length - 5).toDouble();

  void _onFlingTick() {
    final clamped = _fling.value.clamp(0.0, _maxOffset);
    setState(() => _scrollOffset = clamped);
    // 端に到達したらそこで止める
    if (clamped != _fling.value) _fling.stop();
  }

  @override
  void didUpdateWidget(covariant CandlestickChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 時間軸切替などで足が入れ替わったら、古い選択ハイライトを消す
    if (oldWidget.candles.length != widget.candles.length ||
        oldWidget.style != widget.style) {
      _selectedIndex = null;
      _scrollOffset = _scrollOffset.clamp(0, _maxOffset);
    }
  }

  @override
  void dispose() {
    _fling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) {
      return const Center(child: Text('まだ記録がありません'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final visible = _visibleRange(size.width);
        return GestureDetector(
          onScaleStart: (details) {
            _fling.stop();
            _scaleStartWidth = _candleWidth;
            _scaleStartFocalFromRight =
                _scrollOffset +
                (size.width - details.localFocalPoint.dx) / _candleWidth;
          },
          onScaleUpdate: (details) {
            setState(() {
              if (details.pointerCount >= 2) {
                // ピンチ: 指の中心の足がその場に留まるようにズームする
                _candleWidth = (_scaleStartWidth * details.scale).clamp(
                  _minWidth,
                  _maxWidth,
                );
                _scrollOffset =
                    (_scaleStartFocalFromRight -
                            (size.width - details.localFocalPoint.dx) /
                                _candleWidth)
                        .clamp(0, _maxOffset);
              } else {
                // 1本指: パン。focalPointDelta は1フレーム分の差分なので累積。
                // 右へドラッグ = 過去へ戻る（オフセット増加）。
                _scrollOffset =
                    (_scrollOffset + details.focalPointDelta.dx / _candleWidth)
                        .clamp(0, _maxOffset);
              }
            });
          },
          onScaleEnd: (details) {
            // 指を離した速度で慣性スクロール
            final velocity = details.velocity.pixelsPerSecond.dx / _candleWidth;
            if (velocity.abs() < 1) return;
            _fling.animateWith(
              FrictionSimulation(0.135, _scrollOffset, velocity),
            );
          },
          onTapUp: (details) => _handleTap(details.localPosition, size),
          // ダブルタップでズーム・位置を最新にリセット
          onDoubleTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _candleWidth = 14;
              _scrollOffset = 0;
              _selectedIndex = null;
            });
          },
          child: CustomPaint(
            size: size,
            painter: _CandlePainter(
              candles: widget.candles,
              movingAverage: widget.movingAverage,
              candleWidth: _candleWidth,
              firstVisible: visible.$1,
              lastVisible: visible.$2,
              selectedIndex: _selectedIndex,
              style: widget.style,
              theme: Theme.of(context),
            ),
          ),
        );
      },
    );
  }

  /// 表示中の (先頭index, 末尾index)。
  (int, int) _visibleRange(double width) {
    final count = (width / _candleWidth).floor();
    final last = (widget.candles.length - 1 - _scrollOffset.round()).clamp(
      0,
      widget.candles.length - 1,
    );
    final first = max(0, last - count + 1);
    return (first, last);
  }

  void _handleTap(Offset position, Size size) {
    final (first, last) = _visibleRange(size.width);
    final visibleCount = last - first + 1;
    final startX = size.width - visibleCount * _candleWidth;
    final index = first + ((position.dx - startX) / _candleWidth).floor();
    if (index < first || index > last) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
    widget.onSelect?.call(widget.candles[index]);
  }
}

class _CandlePainter extends CustomPainter {
  final List<Candle> candles;
  final List<double?> movingAverage;
  final double candleWidth;
  final int firstVisible;
  final int lastVisible;
  final int? selectedIndex;
  final ChartStyle style;
  final ThemeData theme;

  // 感情の文脈では 緑=良い / 赤=悪い が直感的（仕様書 §5 色のルール）
  static const bullColor = AppColors.bull;
  static const bearColor = AppColors.bear;

  _CandlePainter({
    required this.candles,
    required this.movingAverage,
    required this.candleWidth,
    required this.firstVisible,
    required this.lastVisible,
    required this.selectedIndex,
    required this.style,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final visible = candles.sublist(firstVisible, lastVisible + 1);
    if (visible.isEmpty) return;

    // ラインモードは終値しか描かないので、終値だけでスケーリングする
    var minV = style == ChartStyle.line
        ? visible.map((c) => c.close).reduce(min)
        : visible.map((c) => c.low).reduce(min);
    var maxV = style == ChartStyle.line
        ? visible.map((c) => c.close).reduce(max)
        : visible.map((c) => c.high).reduce(max);
    for (var i = firstVisible; i <= lastVisible; i++) {
      final ma = i < movingAverage.length ? movingAverage[i] : null;
      if (ma != null) {
        minV = min(minV, ma);
        maxV = max(maxV, ma);
      }
    }
    final pad = max((maxV - minV) * 0.1, 1.0);
    minV -= pad;
    maxV += pad;

    const topMargin = 8.0;
    const bottomMargin = 24.0;
    final chartHeight = size.height - topMargin - bottomMargin;
    double yFor(double v) =>
        topMargin + (maxV - v) / (maxV - minV) * chartHeight;

    _drawGrid(canvas, size, minV, maxV, yFor);

    final startX = size.width - visible.length * candleWidth;

    if (style == ChartStyle.line) {
      _drawLine(canvas, visible, startX, yFor);
    } else {
      _drawCandles(canvas, visible, startX, yFor);
    }

    _drawSelection(canvas, startX, topMargin, chartHeight);
    _drawMovingAverage(canvas, startX, yFor);
    _drawDateLabels(canvas, size, visible, startX);
  }

  void _drawCandles(
    Canvas canvas,
    List<Candle> visible,
    double startX,
    double Function(double) yFor,
  ) {
    final bodyWidth = candleWidth * 0.66;
    final wickPaint = Paint()..strokeWidth = max(1, candleWidth / 12);
    final bodyPaint = Paint();

    for (var i = 0; i < visible.length; i++) {
      final c = visible[i];
      final cx = startX + i * candleWidth + candleWidth / 2;
      final color = c.isBullish ? bullColor : bearColor;
      final alpha = c.hasEntry ? 1.0 : 0.45; // 空白日は淡く描く（平穏な日）
      wickPaint.color = color.withValues(alpha: alpha);
      bodyPaint.color = color.withValues(alpha: alpha);

      // ヒゲ
      canvas.drawLine(
        Offset(cx, yFor(c.high)),
        Offset(cx, yFor(c.low)),
        wickPaint,
      );

      // 実体（丸みをつけて柔らかく。同事線に近い時も最低2pxは描く）
      final top = yFor(max(c.open, c.close));
      final bottom = yFor(min(c.open, c.close));
      final rect = Rect.fromLTRB(
        cx - bodyWidth / 2,
        top,
        cx + bodyWidth / 2,
        max(bottom, top + 2),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular((bodyWidth * 0.3).clamp(1.0, 5.0)),
        ),
        bodyPaint,
      );
    }
  }

  /// 日足用: 終値をただの点として描き、線で結ぶ。
  /// 点はその日の方向で緑（プラス）/ 赤（マイナス）に色分けする。
  void _drawLine(
    Canvas canvas,
    List<Candle> visible,
    double startX,
    double Function(double) yFor,
  ) {
    // 線は主張しないニュートラルな色。日の良し悪しは点の色で語る
    final path = Path();
    for (var i = 0; i < visible.length; i++) {
      final cx = startX + i * candleWidth + candleWidth / 2;
      final cy = yFor(visible[i].close);
      if (i == 0) {
        path.moveTo(cx, cy);
      } else {
        path.lineTo(cx, cy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.ink.withValues(alpha: 0.25)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // 記録がある日だけ点を打つ（空白日は線のみ = 平穏な日）。
    // 緑 = その日トータルでプラス、赤 = マイナス。
    final dotRadius = (candleWidth / 4).clamp(2.0, 5.0);
    for (var i = 0; i < visible.length; i++) {
      final c = visible[i];
      if (!c.hasEntry) continue;
      final cx = startX + i * candleWidth + candleWidth / 2;
      final center = Offset(cx, yFor(c.close));
      final color = c.isBullish ? bullColor : bearColor;
      // 白フチをつけて点を際立たせる
      canvas.drawCircle(
        center,
        dotRadius + 1.5,
        Paint()..color = theme.scaffoldBackgroundColor,
      );
      canvas.drawCircle(center, dotRadius, Paint()..color = color);
    }
  }

  void _drawSelection(
    Canvas canvas,
    double startX,
    double topMargin,
    double chartHeight,
  ) {
    final selected = selectedIndex;
    if (selected == null || selected < firstVisible || selected > lastVisible) {
      return;
    }
    final cx =
        startX + (selected - firstVisible) * candleWidth + candleWidth / 2;
    canvas.drawRect(
      Rect.fromLTRB(
        cx - candleWidth / 2,
        topMargin,
        cx + candleWidth / 2,
        topMargin + chartHeight,
      ),
      Paint()
        ..color = theme.colorScheme.primary.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    double minV,
    double maxV,
    double Function(double) yFor,
  ) {
    final gridPaint = Paint()
      ..color = theme.dividerColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    final labelStyle = TextStyle(
      fontSize: 10,
      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
    );
    const divisions = 4;
    for (var i = 0; i <= divisions; i++) {
      final v = minV + (maxV - minV) * i / divisions;
      final y = yFor(v);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: v.toStringAsFixed(0), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, y - tp.height - 2));
    }
  }

  void _drawMovingAverage(
    Canvas canvas,
    double startX,
    double Function(double) yFor,
  ) {
    if (movingAverage.isEmpty) return;
    final path = Path();
    var started = false;
    for (var i = firstVisible; i <= lastVisible; i++) {
      final ma = i < movingAverage.length ? movingAverage[i] : null;
      if (ma == null) continue;
      final cx = startX + (i - firstVisible) * candleWidth + candleWidth / 2;
      if (!started) {
        path.moveTo(cx, yFor(ma));
        started = true;
      } else {
        path.lineTo(cx, yFor(ma));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawDateLabels(
    Canvas canvas,
    Size size,
    List<Candle> visible,
    double startX,
  ) {
    final labelStyle = TextStyle(
      fontSize: 10,
      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
    );
    final step = max(1, (80 / candleWidth).ceil());
    final fmt = DateFormat('M/d');
    for (var i = 0; i < visible.length; i += step) {
      final cx = startX + i * candleWidth + candleWidth / 2;
      final tp = TextPainter(
        text: TextSpan(text: fmt.format(visible[i].date), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - tp.height - 4));
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.candles != candles ||
      old.candleWidth != candleWidth ||
      old.firstVisible != firstVisible ||
      old.lastVisible != lastVisible ||
      old.selectedIndex != selectedIndex ||
      old.style != style ||
      old.movingAverage != movingAverage;
}
