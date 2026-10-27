import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/glass.dart';
import '../../data/providers.dart';

/// A team being set up: its saved id (if reused) and editable names.
class _TeamDraft {
  _TeamDraft({required this.id, required String name, required this.players})
    : name = TextEditingController(text: name);

  String id;
  final TextEditingController name;

  /// One per player slot, in batting order. Saved ids are kept so the
  /// same people keep their stats across matches.
  final List<({String id, TextEditingController name})> players;

  void dispose() {
    name.dispose();
    for (final p in players) {
      p.name.dispose();
    }
  }
}

/// Everything before the first ball: format, teams and toss. Prefilled from
/// the last match, so starting can be a single tap.
class NewMatchScreen extends ConsumerStatefulWidget {
  const NewMatchScreen({super.key});

  @override
  ConsumerState<NewMatchScreen> createState() => _NewMatchScreenState();
}

class _NewMatchScreenState extends ConsumerState<NewMatchScreen> {
  static const _uuid = Uuid();
  static const _formats = [
    MatchRules.t20,
    MatchRules.odi,
    MatchRules.t10,
    MatchRules.hundred,
    MatchRules.test,
    MatchRules.firstClass,
  ];

  MatchRules? _preset = MatchRules.t20; // null = custom
  int _customOvers = 8;
  int _customPlayers = 8;

  /// Custom matches: one innings each with an overs limit, or two innings
  /// each over a number of days.
  var _customTwoInnings = false;
  int _customDays = 2;
  _TeamDraft? _a;
  _TeamDraft? _b;
  int _tossWinner = 0;
  var _tossDecision = TossDecision.bat;
  String? _error;
  var _starting = false;

  MatchRules get _rules =>
      _preset ??
      (_customTwoInnings
          ? MatchRules.multiDay(
              days: _customDays,
              playersPerSide: _customPlayers,
            )
          : MatchRules.custom(
              overs: _customOvers,
              playersPerSide: _customPlayers,
            ));

  @override
  void dispose() {
    _a?.dispose();
    _b?.dispose();
    super.dispose();
  }

  /// Fills the two teams from the most recently used saved teams.
  void _prefill(
    List<({String id, String name, List<PlayerRef> players})> saved,
  ) {
    if (_a != null) return;
    _TeamDraft draft(int i, String fallback) {
      final s = i < saved.length ? saved[i] : null;
      return _TeamDraft(
        id: s?.id ?? _uuid.v4(),
        name: s?.name ?? fallback,
        players: [
          for (final p in s?.players ?? const <PlayerRef>[])
            (id: p.id, name: TextEditingController(text: p.name)),
        ],
      );
    }

    _a = draft(0, 'Team A');
    _b = draft(1, 'Team B');
  }

  /// Makes each team exactly as long as the format needs.
  List<PlayerRef> _lineUp(_TeamDraft t) {
    final n = _rules.playersPerSide;
    while (t.players.length < n) {
      t.players.add((id: _uuid.v4(), name: TextEditingController()));
    }
    return [
      for (var i = 0; i < n; i++)
        PlayerRef(
          id: t.players[i].id,
          name: t.players[i].name.text.trim().isEmpty
              ? 'Player ${i + 1}'
              : t.players[i].name.text.trim(),
        ),
    ];
  }

  Future<void> _start() async {
    final a = _a!;
    final b = _b!;
    final nameA = a.name.text.trim().isEmpty ? 'Team A' : a.name.text.trim();
    final nameB = b.name.text.trim().isEmpty ? 'Team B' : b.name.text.trim();
    if (a.id == b.id || nameA.toLowerCase() == nameB.toLowerCase()) {
      setState(() => _error = 'Choose two different teams.');
      return;
    }
    final teamA = TeamSheet(id: a.id, name: nameA, players: _lineUp(a));
    final teamB = TeamSheet(id: b.id, name: nameB, players: _lineUp(b));
    final setup = MatchSetup(
      rules: _rules,
      teamA: teamA,
      teamB: teamB,
      toss: Toss(
        wonByTeamId: _tossWinner == 0 ? teamA.id : teamB.id,
        decision: _tossDecision,
      ),
    );
    final problems = setup.validate();
    if (problems.isNotEmpty) {
      setState(() => _error = problems.first);
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    final teams = ref.read(teamRepositoryProvider);
    await teams.save(teamA);
    await teams.save(teamB);
    final id = await ref.read(matchRepositoryProvider).create(setup);
    if (mounted) context.pushReplacement(Routes.match(id));
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedTeamsProvider);
    if (saved case AsyncData(:final value)) _prefill(value);
    final a = _a;
    final b = _b;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return GlassScaffold(
      appBar: AppBar(title: const Text('New match')),
      body: a == null || b == null
          ? const SizedBox.shrink()
          : SafeArea(
              // A short form, built in full so every field is reachable.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Label('Format'),
                    GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final f in _formats)
                                ChoiceChip(
                                  label: Text(f.name),
                                  selected: _preset == f,
                                  onSelected: (_) =>
                                      setState(() => _preset = f),
                                ),
                              ChoiceChip(
                                label: const Text('Custom'),
                                selected: _preset == null,
                                onSelected: (_) =>
                                    setState(() => _preset = null),
                              ),
                            ],
                          ),
                          if (_preset == null) ...[
                            const SizedBox(height: 12),
                            _Segments(
                              key: const Key('customInnings'),
                              labels: const ['One innings', 'Two innings'],
                              selected: _customTwoInnings ? 1 : 0,
                              onSelected: (i) =>
                                  setState(() => _customTwoInnings = i == 1),
                            ),
                            const SizedBox(height: 4),
                            if (_customTwoInnings)
                              _Stepper(
                                key: const Key('customDays'),
                                label: 'Days',
                                value: _customDays,
                                min: 1,
                                max: 5,
                                onChanged: (v) =>
                                    setState(() => _customDays = v),
                              )
                            else
                              _Stepper(
                                label: 'Overs a side',
                                value: _customOvers,
                                min: 1,
                                max: 50,
                                onChanged: (v) =>
                                    setState(() => _customOvers = v),
                              ),
                            _Stepper(
                              label: 'Players a side',
                              value: _customPlayers,
                              min: 2,
                              max: 11,
                              onChanged: (v) =>
                                  setState(() => _customPlayers = v),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            _summary(_rules),
                            style: text.bodySmall?.copyWith(
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const _Label('Teams'),
                    _TeamEditor(
                      key: const Key('teamA'),
                      draft: a,
                      players: _rules.playersPerSide,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    _TeamEditor(
                      key: const Key('teamB'),
                      draft: b,
                      players: _rules.playersPerSide,
                      onChanged: () => setState(() {}),
                    ),
                    const _Label('Toss'),
                    GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Won by', style: TextStyle(color: colors.muted)),
                          const SizedBox(height: 8),
                          _Segments(
                            labels: [
                              _shown(a.name.text, 'Team A'),
                              _shown(b.name.text, 'Team B'),
                            ],
                            selected: _tossWinner,
                            onSelected: (i) => setState(() => _tossWinner = i),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Chose to',
                            style: TextStyle(color: colors.muted),
                          ),
                          const SizedBox(height: 8),
                          _Segments(
                            labels: const ['Bat', 'Bowl'],
                            selected: _tossDecision == TossDecision.bat ? 0 : 1,
                            onSelected: (i) => setState(
                              () => _tossDecision = i == 0
                                  ? TossDecision.bat
                                  : TossDecision.bowl,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: text.bodyMedium?.copyWith(color: colors.wicket),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('startMatch'),
                      onPressed: _starting ? null : _start,
                      child: const Text('Start match'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  static String _shown(String name, String fallback) =>
      name.trim().isEmpty ? fallback : name.trim();

  static String _summary(MatchRules r) {
    final balls = r.ballsPerInnings;
    final perBowler = r.bowlerLimit.maxBalls(
      inningsBalls: balls,
      ballsPerOver: r.ballsPerOver,
    );
    if (r.isTwoInnings) {
      final days = r.days;
      return [
        if (days != null) days == 1 ? '1 day' : '$days days',
        'two innings each',
        '${r.playersPerSide} players',
        if (r.followOnMargin case final m?) 'follow-on at $m',
        'declarations',
      ].join(' · ');
    }
    return [
      if (balls != null)
        r.ballsPerOver == 5
            ? '$balls balls a side'
            : '${balls ~/ r.ballsPerOver} overs a side',
      '${r.playersPerSide} players',
      if (perBowler != null)
        r.ballsPerOver == 5
            ? '$perBowler balls per bowler'
            : '${perBowler ~/ r.ballsPerOver} overs per bowler',
      if (r.freeHitAfterNoBall) 'free hit after a no-ball',
      if (r.tieBreak != TieBreak.none) 'super over if tied',
    ].join(' · ');
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: context.colors.muted,
        letterSpacing: 1.2,
      ),
    ),
  );
}

/// Two or more options, one selected; large targets for outdoor use.
class _Segments extends StatelessWidget {
  const _Segments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SegmentedButton<int>(
    segments: [
      for (var i = 0; i < labels.length; i++)
        ButtonSegment(
          value: i,
          label: Text(labels[i], overflow: TextOverflow.ellipsis),
        ),
    ],
    selected: {selected},
    showSelectedIcon: false,
    onSelectionChanged: (s) => onSelected(s.single),
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      IconButton(
        tooltip: 'Fewer',
        onPressed: value > min ? () => onChanged(value - 1) : null,
        icon: const Icon(Icons.remove_circle_outline),
      ),
      SizedBox(
        width: 36,
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      IconButton(
        tooltip: 'More',
        onPressed: value < max ? () => onChanged(value + 1) : null,
        icon: const Icon(Icons.add_circle_outline),
      ),
    ],
  );
}

/// Team name, with the player names folded away until wanted.
class _TeamEditor extends StatelessWidget {
  const _TeamEditor({
    super.key,
    required this.draft,
    required this.players,
    required this.onChanged,
  });

  final _TeamDraft draft;
  final int players;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    while (draft.players.length < players) {
      draft.players.add((id: const Uuid().v4(), name: TextEditingController()));
    }
    final named = draft.players
        .take(players)
        .where((p) => p.name.text.trim().isNotEmpty)
        .length;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: TextField(
            controller: draft.name,
            textCapitalization: TextCapitalization.words,
            style: Theme.of(context).textTheme.titleLarge,
            decoration: const InputDecoration(
              labelText: 'Team name',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: (_) => onChanged(),
          ),
          subtitle: Text(
            named == 0
                ? 'Player names optional'
                : '$named of $players players named',
            style: TextStyle(color: colors.muted),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (var i = 0; i < players; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: draft.players[i].name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '${i + 1}',
                    hintText: 'Player ${i + 1}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
