import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// One point on a trend.
///
/// [isInterpolated] is not decoration. A daily figure derived by apportioning
/// an interval between two readings is a model, and a chart that draws it
/// identically to a measured point is the single most effective way this
/// product could mislead someone into a dispute they will lose.
class TrendPoint {
  const TrendPoint({
    required this.date,
    required this.value,
    this.from,
    this.isInterpolated = false,
    this.isExcluded = false,
  });

  /// Where the period this point measures began.
  ///
  /// A point plotted at a reading is a *rate over the span since the last
  /// one*, not a value on a day. The read-out says so — "1–6 Aug" rather
  /// than "6 Aug" — because the difference is the difference between a
  /// figure somebody can check against their meter and one they cannot.
  final DateTime? from;

  final DateTime date;
  final double value;
  final bool isInterpolated;

  /// Flagged, and therefore outside the baseline. Drawn, but hollow.
  final bool isExcluded;
}

/// A scrubbable line chart, painted rather than plotted by a package.
///
/// Painted by hand for two reasons. The interpolation distinction above is
/// not something chart packages model, and hanging it off a colour callback
/// in someone else's API is a fragile place for a load-bearing rule to live.
/// And the low-end Android in the test matrix has to hold 60 fps while a
/// finger drags across it, which is easier to guarantee when the paint path
/// is a few dozen lines you can read.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.valueLabel,
    this.height = 200,
    this.formatValue,
    this.accent,
    this.compact = false,
  });

  final List<TrendPoint> points;

  /// Unit shown against the scrubbed value: 'kWh', '₦'.
  final String valueLabel;

  final double height;
  final String Function(double)? formatValue;
  final Color? accent;

  /// Drops the scrub read-out and the legend. For a preview that links
  /// somewhere the full chart lives — a home-screen card is a glance, and a
  /// glance with a legend under it is not one.
  final bool compact;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _scrubIndex;

  void _scrubTo(Offset local, double width) {
    if (widget.points.length < 2) return;
    final step = width / (widget.points.length - 1);
    final index =
        (local.dx / step).round().clamp(0, widget.points.length - 1);
    if (index != _scrubIndex) setState(() => _scrubIndex = index);
  }

  /// The read-out stays after the finger lifts.
  ///
  /// Clearing on release is the desktop behaviour and it is wrong here: the
  /// finger covers the chart while it is down, so the only moment the user
  /// can actually read the value is the moment a clearing gesture would
  /// erase it.
  void _clear() => setState(() => _scrubIndex = null);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final accent = widget.accent ?? c.brand;

    if (widget.points.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Not enough readings yet to draw a trend.',
            style: t.caption.copyWith(color: c.textTertiary),
          ),
        ),
      );
    }

    final scrubbed =
        _scrubIndex == null ? null : widget.points[_scrubIndex!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The read-out sits above the chart rather than in a floating
        // tooltip: a tooltip under a fingertip is a tooltip nobody can read.
        if (!widget.compact)
        SizedBox(
          height: 44,
          child: scrubbed == null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Touch the chart to read any period.',
                    style: t.caption.copyWith(color: c.textTertiary),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.formatValue?.call(scrubbed.value) ??
                          scrubbed.value.toStringAsFixed(1),
                      style: t.headline.copyWith(
                        color: scrubbed.isInterpolated
                            ? c.estimate
                            : c.textPrimary,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        widget.valueLabel,
                        style: t.caption.copyWith(color: c.textSecondary),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _spanLabel(scrubbed) +
                          (scrubbed.isInterpolated ? ' · estimated' : ''),
                      style: t.caption.copyWith(
                        color: scrubbed.isInterpolated
                            ? c.estimate
                            : c.textSecondary,
                      ),
                    ),
                  ],
                ),
        ),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _scrubTo(d.localPosition, constraints.maxWidth),
                onHorizontalDragStart: (d) =>
                    _scrubTo(d.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _scrubTo(d.localPosition, constraints.maxWidth),
                onLongPress: _clear,
                child: CustomPaint(
                  size: Size(constraints.maxWidth, widget.height),
                  painter: _TrendPainter(
                    points: widget.points,
                    accent: accent,
                    estimate: c.estimate,
                    grid: c.outline,
                    surface: c.surface,
                    scrubIndex: _scrubIndex,
                    textColour: c.textTertiary,
                  ),
                ),
              );
            },
          ),
        ),
        if (!widget.compact) ...[
          const SizedBox(height: Space.sm),
          _Legend(accent: accent),
        ],
      ],
    );
  }
}

String _spanLabel(TrendPoint p) {
  final f = p.from;
  if (f == null) return _dayLabel(p.date);
  final sameMonth = f.month == p.date.month;
  return sameMonth
      ? '${f.day}–${_dayLabel(p.date)}'
      : '${_dayLabel(f)} – ${_dayLabel(p.date)}';
}

String _dayLabel(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}

class _Legend extends StatelessWidget {
  const _Legend({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Row(
      children: [
        _Swatch(colour: accent, label: 'Measured'),
        const SizedBox(width: Space.lg),
        _Swatch(colour: c.estimate, label: 'Estimated', dashed: true),
        const Spacer(),
        Text(
          '${_dayLabel(DateTime.now())} · today',
          style: t.caption.copyWith(color: c.textTertiary),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colour,
    required this.label,
    this.dashed = false,
  });

  final Color colour;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(14, 2),
          painter: _SwatchPainter(colour: colour, dashed: dashed),
        ),
        const SizedBox(width: Space.xs),
        Text(label, style: t.caption.copyWith(color: c.textTertiary)),
      ],
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({required this.colour, required this.dashed});

  final Color colour;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (!dashed) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + 3, size.width), size.height / 2),
        paint,
      );
      x += 6;
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.colour != colour || old.dashed != dashed;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.accent,
    required this.estimate,
    required this.grid,
    required this.surface,
    required this.scrubIndex,
    required this.textColour,
  });

  final List<TrendPoint> points;
  final Color accent;
  final Color estimate;
  final Color grid;
  final Color surface;
  final int? scrubIndex;
  final Color textColour;

  static const double _padTop = 12;
  static const double _padBottom = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.map((p) => p.value).toList();
    final maxV = values.reduce(math.max);
    final minV = math.min(0.0, values.reduce(math.min));
    // A flat series would divide by zero and, worse, draw a line pinned to
    // the top of the box as though it were a maximum.
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;

    final chartHeight = size.height - _padTop - _padBottom;
    final step = size.width / (points.length - 1);

    Offset at(int i) => Offset(
          i * step,
          _padTop + chartHeight * (1 - (points[i].value - minV) / span),
        );

    // --- gridlines ---------------------------------------------------------
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = _padTop + chartHeight * g / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // --- fill under the line ----------------------------------------------
    final fill = Path()..moveTo(0, _padTop + chartHeight);
    for (var i = 0; i < points.length; i++) {
      fill.lineTo(at(i).dx, at(i).dy);
    }
    fill.lineTo(size.width, _padTop + chartHeight);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, _padTop),
          Offset(0, _padTop + chartHeight),
          [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0)],
        ),
    );

    // --- the line, segment by segment -------------------------------------
    // Drawn per segment rather than as one path so an interpolated stretch
    // can be dashed. A single path with one colour would have been half the
    // code and would have quietly erased the distinction the whole chart
    // exists to preserve.
    final linePaint = Paint()
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 1; i < points.length; i++) {
      final modelled = points[i].isInterpolated || points[i - 1].isInterpolated;
      linePaint.color = modelled ? estimate : accent;
      final a = at(i - 1);
      final b = at(i);
      if (modelled) {
        _dashedLine(canvas, a, b, linePaint);
      } else {
        canvas.drawLine(a, b, linePaint);
      }
    }

    // --- excluded points ---------------------------------------------------
    for (var i = 0; i < points.length; i++) {
      if (!points[i].isExcluded) continue;
      canvas.drawCircle(
        at(i),
        4,
        Paint()
          ..color = surface
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        at(i),
        4,
        Paint()
          ..color = textColour
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    // --- scrub -------------------------------------------------------------
    final s = scrubIndex;
    if (s != null) {
      final p = at(s);
      canvas.drawLine(
        Offset(p.dx, _padTop),
        Offset(p.dx, _padTop + chartHeight),
        Paint()
          ..color = textColour
          ..strokeWidth = 1,
      );
      final dot = points[s].isInterpolated ? estimate : accent;
      canvas.drawCircle(p, 7, Paint()..color = surface);
      canvas.drawCircle(p, 5, Paint()..color = dot);
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 3.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = math.min(travelled + dash, total);
      canvas.drawLine(a + dir * travelled, a + dir * end, paint);
      travelled = end + gap;
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.scrubIndex != scrubIndex ||
      old.points != points ||
      old.accent != accent;
}
