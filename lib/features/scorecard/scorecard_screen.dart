import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../scoring/scoring_logic.dart';
import '../scoring/widgets/score_panels.dart';
import 'charts.dart';

/// The full scorecard: one tab per innings, then the charts.
class ScorecardScreen extends ConsumerWidget {
  const ScorecardScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(matchControllerProvider(matchId));
    final match = async.value;
    if (match == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.hasError
            ? const Center(child: Text('This match could not be opened.'))
            : const SizedBox.shrink(),
      );
    }
    final setup = match.setup;
    final innings = [
      for (final inn in match.state.innings)
        if (inn.openersOrBalls) inn,
    ];
    final result = match.state.result;
    return DefaultTabController(
      length: innings.length + 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${setup.teamA.name} v ${setup.teamB.name}'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final inn in innings) Tab(text: inningsLabel(match, inn)),
              const Tab(key: Key('chartsTab'), text: 'Charts'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  result.describe(setup),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: context.colors.runs),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final inn in innings)
                    _InningsCard(match: match, innings: inn),
                  ChartsView(match: match),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Lions" or "Lions 2nd inns" or "Lions super over".
String inningsLabel(Match match, InningsState inn) {
  final name = match.setup.team(inn.battingTeamId).name;
  if (inn.kind == InningsKind.superOver) return '$name super over';
  if (!match.setup.rules.isTwoInnings) return name;
  final nth = match.state.innings
      .where(
        (i) => i.battingTeamId == inn.battingTeamId && i.number <= inn.number,
      )
      .length;
  return '$name ${nth == 1 ? '1st' : '2nd'} inns';
}

extension on InningsState {
  /// Worth a tab: the innings has started.
  bool get openersOrBalls => batters.isNotEmpty || runs > 0 || isClosed;
}

class _InningsCard extends StatelessWidget {
  const _InningsCard({required this.match, required this.innings});

  final Match match;
  final InningsState innings;

  @override
  Widget build(BuildContext context) {
    final inn = innings;
    final setup = match.setup;
    final nameOf = nameLookup(setup);
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final batted = inn.batters.map((b) => b.playerId).toSet();
    final yetToBat = [
      for (final p in setup.team(inn.battingTeamId).players)
        if (!batted.contains(p.id)) p.id,
    ];
    final e = inn.extras;
    final muted = TextStyle(color: colors.muted);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          '${inn.runs}/${inn.wickets}  (${oversLabel(inn)})',
          style: text.headlineMedium,
        ),
        Text(
          [
            'Run rate ${inn.runRate.toStringAsFixed(2)}',
            if (inn.target != null) 'Target ${inn.target}',
          ].join(' · '),
          style: muted,
        ),
        const SizedBox(height: 16),
        _Table(
          header: const ['Batter', 'R', 'B', '4s', '6s', 'SR'],
          rows: [
            for (final b in inn.batters)
              _Row(
                key: Key('bat-${b.playerId}'),
                title: nameOf(b.playerId),
                subtitle: howOut(b, nameOf),
                bold: b.status == BatterStatus.batting,
                cells: [
                  '${b.runs}',
                  '${b.balls}',
                  '${b.fours}',
                  '${b.sixes}',
                  b.strikeRate.toStringAsFixed(1),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        _Line(
          'Extras',
          '${e.total}',
          detail:
              'wd ${e.wides}, nb ${e.noBalls}, b ${e.byes}, '
              'lb ${e.legByes}${e.penalty > 0 ? ', pen ${e.penalty}' : ''}',
        ),
        _Line(
          'Total',
          '${inn.runs}/${inn.wickets}',
          detail: oversLabel(inn),
          bold: true,
        ),
        if (yetToBat.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${inn.isClosed ? 'Did not bat' : 'Yet to bat'}: '
            '${yetToBat.map(nameOf).join(', ')}',
            style: muted,
          ),
        ],
        if (inn.fallOfWickets.isNotEmpty) ...[
          const _Heading('Fall of wickets'),
          Text(
            [
              for (final f in inn.fallOfWickets)
                '${f.wicket}-${f.runs} (${nameOf(f.batterId)}, '
                    '${formatOvers(f.legalBalls, inn.ballsPerOver)})',
            ].join(' · '),
          ),
        ],
        if (inn.bowlers.isNotEmpty) ...[
          const _Heading('Bowling'),
          _Table(
            header: const ['Bowler', 'O', 'M', 'R', 'W', 'Econ'],
            rows: [
              for (final b in inn.bowlers)
                _Row(
                  key: Key('bowl-${b.playerId}'),
                  title: nameOf(b.playerId),
                  subtitle: [
                    if (b.wides > 0) '${b.wides} wd',
                    if (b.noBalls > 0) '${b.noBalls} nb',
                    '${b.dots} dots',
                  ].join(', '),
                  cells: [
                    formatOvers(b.legalBalls, inn.ballsPerOver),
                    '${b.maidens}',
                    '${b.runs}',
                    '${b.wickets}',
                    b.economy(inn.ballsPerOver).toStringAsFixed(2),
                  ],
                ),
            ],
          ),
        ],
        if (inn.partnerships.isNotEmpty) ...[
          const _Heading('Partnerships'),
          for (final p in inn.partnerships)
            _Line(
              p.batterIds.map(nameOf).join(' & '),
              '${p.runs} (${p.balls})',
            ),
        ],
        if (inn.overs.isNotEmpty) ...[
          const _Heading('Overs'),
          for (final over in inn.overs.reversed)
            if (over.deliveries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Over ${over.number}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${over.runs} runs',
                            style: muted.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            over.bowlerIds.map(nameOf).join(', '),
                            style: muted.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final d in over.deliveries)
                                BallChip(record: d, rules: setup.rules),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: context.colors.muted,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.detail, this.bold = false});

  final String label;
  final String value;
  final String? detail;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final weight = bold ? FontWeight.w700 : FontWeight.w500;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontWeight: weight)),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detail!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.colors.muted, fontSize: 13),
              ),
            ),
          ] else
            const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: weight,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row {
  const _Row({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.cells,
    this.bold = false,
  });

  final Key key;
  final String title;
  final String subtitle;
  final List<String> cells;
  final bool bold;
}

/// A name column that takes the room left, then narrow numeric columns.
class _Table extends StatelessWidget {
  const _Table({required this.header, required this.rows});

  final List<String> header;
  final List<_Row> rows;

  static const _widths = [36.0, 36.0, 32.0, 32.0, 50.0];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const numbers = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    Widget cells(List<String> values, TextStyle style) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < values.length; i++)
          SizedBox(
            width: _widths[i],
            child: Text(values[i], textAlign: TextAlign.right, style: style),
          ),
      ],
    );
    final headStyle = TextStyle(color: colors.muted, fontSize: 12);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(header.first, style: headStyle)),
            cells(header.sublist(1), headStyle),
          ],
        ),
        Divider(color: colors.line, height: 12),
        for (final r in rows)
          Padding(
            key: r.key,
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: r.bold
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      Text(
                        r.subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                cells(r.cells, numbers),
              ],
            ),
          ),
      ],
    );
  }
}
