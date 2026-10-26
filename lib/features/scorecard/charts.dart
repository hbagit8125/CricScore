import 'dart:math' as math;

import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/glass.dart';
import 'scorecard_screen.dart';

/// Series colours, checked for colour-blind separation and contrast against
/// each theme's card surface. The first innings is always green.
const _seriesLight = [Color(0xFF1F8A4C), Color(0xFF2F5FD0)];
const _seriesDark = [Color(0xFF25A85C), Color(0xFF5B8DEF)];

/// Runs and wickets per over for one innings.
final class ChartSeries {
  ChartSeries({required this.label, required this.overs});

  factory ChartSeries.of(Match match, InningsState inn) => ChartSeries(
    label: inningsLabel(match, inn),
    overs: [
      for (final o in inn.overs)
        if (o.deliveries.isNotEmpty)
          (
            runs: o.runs,
            wickets: o.deliveries
                .where((d) => d.delivery.dismissal != null)
                .length,
            total: o.deliveries.last.teamRuns,
          ),
    ],
  );

  final String label;

  /// Wickets here count dismissals on deliveries; retirements and run outs
  /// before a ball are not plotted.
  final List<({int runs, int wickets, int total})> overs;
}

/// The worm (cumulative runs) and Manhattan (runs per over), with a tap to
/// read any over.
class ChartsView extends StatefulWidget {
  const ChartsView({super.key, required this.match});

  final Match match;

  @override
  State<ChartsView> createState() => _ChartsViewState();
}

class _ChartsViewState extends State<ChartsView> {
  int? _over;
  var _pair = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final match = widget.match;
    final regular = [
      for (final inn in match.state.innings)
        if (inn.kind == InningsKind.regular && inn.overs.isNotEmpty) inn,
    ];
    if (regular.isEmpty) {
      return Center(
        child: Text(
          'Charts appear once play starts.',
          style: TextStyle(color: colors.muted),
        ),
      );
    }
    // Two-innings matches compare one round of innings at a time.
    final pairs = (regular.length + 1) ~/ 2;
    final pair = math.min(_pair, pairs - 1);
    final series = [
      for (final inn in regular.skip(pair * 2).take(2))
        ChartSeries.of(match, inn),
    ];
    final palette = Theme.of(context).brightness == Brightness.dark
        ? _seriesDark
        : _seriesLight;
    final maxOvers = series.map((s) => s.overs.length).reduce(math.max);
    final selected = _over == null ? null : math.min(_over!, maxOvers - 1);

    void select(double fraction) => setState(
      () => _over = (fraction * maxOvers).floor().clamp(0, maxOvers - 1),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (pairs > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegmentedButton<int>(
              segments: [
                for (var i = 0; i < pairs; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(i == 0 ? '1st innings' : '2nd innings'),
                  ),
              ],
              selected: {pair},
              onSelectionChanged: (v) => setState(() => _pair = v.single),
            ),
          ),
        // Legend: identity never relies on colour alone.
        Wrap(
          spacing: 16,
          children: [
            for (var i = 0; i < series.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: palette[i],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(series[i].label),
                ],
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 10, color: colors.wicket),
                const SizedBox(width: 6),
                const Text('Wicket'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Readout(series: series, over: selected),
        const _Title('Worm'),
        _ChartFrame(
          key: const Key('worm'),
          onSelect: select,
          painter: _WormPainter(
            series: series,
            palette: palette,
            colors: colors,
            maxOvers: maxOvers,
            selected: selected,
          ),
        ),
        const _Title('Runs per over'),
        _ChartFrame(
          key: const Key('manhattan'),
          onSelect: select,
          painter: _ManhattanPainter(
            series: series,
            palette: palette,
            colors: colors,
            maxOvers: maxOvers,
            selected: selected,
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(label, style: Theme.of(context).textTheme.titleLarge),
  );
}

/// What the selected over held, in text, for every series.
class _Readout extends StatelessWidget {
  const _Readout({required this.series, required this.over});

  final List<ChartSeries> series;
  final int? over;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.colors.muted);
    final o = over;
    if (o == null) return Text('Tap a chart to see any over.', style: muted);
    final lines = [
      for (final s in series)
        if (o < s.overs.length)
          '${s.label}: ${s.overs[o].runs} '
              '${s.overs[o].runs == 1 ? 'run' : 'runs'}'
              '${s.overs[o].wickets > 0 ? ', ${s.overs[o].wickets} wkt' : ''}'
              ' · ${s.overs[o].total} after the over',
    ];
    return Column(
      key: const Key('chartReadout'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Over ${o + 1}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        for (final l in lines) Text(l),
      ],
    );
  }
}

class _ChartFrame extends StatelessWidget {
  const _ChartFrame({super.key, required this.painter, required this.onSelect});

  final CustomPainter painter;

  /// Called with the horizontal position, 0 to 1, across the plot area.
  final ValueChanged<double> onSelect;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.fromLTRB(4, 12, 12, 4),
    child: SizedBox(
      height: 184,
      child: LayoutBuilder(
        builder: (context, box) {
          void at(Offset p) => onSelect(
            ((p.dx - _Plot.left) / (box.maxWidth - _Plot.left)).clamp(0, 0.999),
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => at(d.localPosition),
            onHorizontalDragUpdate: (d) => at(d.localPosition),
            child: CustomPaint(painter: painter, size: Size.infinite),
          );
        },
      ),
    ),
  );
}

/// Shared axes: a recessive grid with a few round values on the left and
/// over numbers along the bottom.
abstract class _Plot extends CustomPainter {
  _Plot({
    required this.series,
    required this.palette,
    required this.colors,
    required this.maxOvers,
    required this.selected,
  });

  static const left = 32.0;
  static const bottom = 18.0;

  final List<ChartSeries> series;
  final List<Color> palette;
  final AppColors colors;
  final int maxOvers;
  final int? selected;

  int get maxValue;

  late Rect plot;
  late double top;

  @override
  void paint(Canvas canvas, Size size) {
    plot = Rect.fromLTRB(left, 4, size.width, size.height - bottom);
    final step = _niceStep(maxValue);
    top = math.max(step, (maxValue / step).ceil() * step).toDouble();
    final grid = Paint()
      ..color = colors.line
      ..strokeWidth = 1;
    for (var v = 0.0; v <= top; v += step) {
      final y = yOf(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(canvas, v.toInt().toString(), Offset(0, y - 7), width: left - 6);
    }
    final every = maxOvers <= 10 ? 1 : (maxOvers <= 25 ? 5 : 10);
    for (var o = every; o <= maxOvers; o += every) {
      _text(
        canvas,
        '$o',
        Offset(xOfOver(o - 1) - 12, plot.bottom + 3),
        width: 24,
        align: TextAlign.center,
      );
    }
    if (selected case final s?) {
      final x = xOfOver(s);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = colors.muted
          ..strokeWidth = 1,
      );
    }
    paintData(canvas);
  }

  void paintData(Canvas canvas);

  double get slot => plot.width / maxOvers;

  /// Centre of over [index] (0-based).
  double xOfOver(int index) => plot.left + slot * (index + 0.5);

  double yOf(num value) => plot.bottom - plot.height * value / top;

  void wicketDot(Canvas canvas, Offset at) {
    canvas
      ..drawCircle(
        at,
        5,
        Paint()..color = Color.alphaBlend(colors.surface, colors.background),
      )
      ..drawCircle(at, 4, Paint()..color = colors.wicket);
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    required double width,
    TextAlign align = TextAlign.right,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: colors.muted,
          fontSize: 11,
          fontFamily: AppFonts.body,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, at);
  }

  static int _niceStep(int max) {
    final raw = math.max(1, max) / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 5, 10]) {
      if (m * mag >= raw) return math.max(1, (m * mag).round());
    }
    return math.max(1, (10 * mag).round());
  }

  @override
  bool shouldRepaint(covariant _Plot old) =>
      old.series != series ||
      old.selected != selected ||
      old.palette != palette ||
      old.colors != colors;
}

class _WormPainter extends _Plot {
  _WormPainter({
    required super.series,
    required super.palette,
    required super.colors,
    required super.maxOvers,
    required super.selected,
  });

  @override
  int get maxValue => series
      .map((s) => s.overs.isEmpty ? 0 : s.overs.last.total)
      .reduce(math.max);

  // The worm runs from the origin to the end of each over.
  double _xEnd(int index) => plot.left + slot * (index + 1);

  @override
  double xOfOver(int index) => _xEnd(index);

  @override
  void paintData(Canvas canvas) {
    for (var i = 0; i < series.length; i++) {
      final s = series[i];
      final path = Path()..moveTo(plot.left, plot.bottom);
      for (var o = 0; o < s.overs.length; o++) {
        path.lineTo(_xEnd(o), yOf(s.overs[o].total));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = palette[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
    for (final s in series) {
      for (var o = 0; o < s.overs.length; o++) {
        if (s.overs[o].wickets > 0) {
          wicketDot(canvas, Offset(_xEnd(o), yOf(s.overs[o].total)));
        }
      }
    }
  }
}

class _ManhattanPainter extends _Plot {
  _ManhattanPainter({
    required super.series,
    required super.palette,
    required super.colors,
    required super.maxOvers,
    required super.selected,
  });

  @override
  int get maxValue => series
      .expand((s) => s.overs)
      .map((o) => o.runs + (o.wickets > 0 ? 3 : 0))
      .fold(0, math.max);

  @override
  void paintData(Canvas canvas) {
    const gap = 2.0;
    final n = series.length;
    // Thin bars even when only a few overs have been bowled.
    final barWidth = (slot - gap * (n + 1)) / n;
    final width = barWidth.clamp(1.0, 20.0);
    final inset = (slot - n * width - (n - 1) * gap) / 2;
    for (var i = 0; i < n; i++) {
      final s = series[i];
      for (var o = 0; o < s.overs.length; o++) {
        final x = plot.left + slot * o + inset + i * (width + gap);
        final y = yOf(s.overs[o].runs);
        final radius = Radius.circular(math.min(4, width / 2));
        if (s.overs[o].runs > 0) {
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTRB(x, y, x + width, plot.bottom),
              topLeft: radius,
              topRight: radius,
            ),
            Paint()..color = palette[i],
          );
        }
        for (var w = 0; w < s.overs[o].wickets; w++) {
          wicketDot(canvas, Offset(x + width / 2, y - 7 - w * 10));
        }
      }
    }
  }
}
