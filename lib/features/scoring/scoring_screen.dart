import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import 'scoring_logic.dart';
import 'widgets/keypad.dart';
import 'widgets/score_panels.dart';
import 'widgets/sheets.dart';

/// Scores one match. The keypad is always on screen; anything only the
/// scorer can answer (openers, bowler, next batter) is asked for with the
/// likely answer pre-selected.
class ScoringScreen extends ConsumerStatefulWidget {
  const ScoringScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends ConsumerState<ScoringScreen> {
  var _armed = ArmedExtra.none;

  /// Event count at which a question was last shown, so a sheet the scorer
  /// dismissed is not pushed again until something changes.
  int? _askedAt;
  bool _asking = false;

  MatchController get _controller =>
      ref.read(matchControllerProvider(widget.matchId).notifier);

  Match? get _match => ref.read(matchControllerProvider(widget.matchId)).value;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(matchControllerProvider(widget.matchId));
    ref.listen(matchControllerProvider(widget.matchId), (_, next) {
      if (next case AsyncData(:final value)) _react(value);
    });

    return switch (async) {
      AsyncData(:final value) => _scaffold(value),
      AsyncError(:final error) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('This match could not be opened.\n$error')),
      ),
      _ => const Scaffold(body: SizedBox.shrink()),
    };
  }

  Widget _scaffold(Match match) {
    // First open: ask whatever is pending once the frame is built.
    if (_askedAt == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _react(match));
    }
    final state = match.state;
    final setup = match.setup;
    final inn = state.currentInnings!;
    final nameOf = nameLookup(setup);
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${setup.teamA.name} v ${setup.teamB.name}'),
            Text(
              setup.rules.name,
              style: TextStyle(fontSize: 13, color: colors.muted),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ScoreHeader(innings: inn, setup: setup),
                      const SizedBox(height: 14),
                      if (inn.batters.isNotEmpty) ...[
                        BattersPanel(innings: inn, nameOf: nameOf),
                        const SizedBox(height: 8),
                        BowlerPanel(innings: inn, nameOf: nameOf),
                        const SizedBox(height: 14),
                        OverStrip(innings: inn, rules: setup.rules),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _bottom(match),
            ],
          ),
        ),
      ),
    );
  }

  /// The keypad, or what to do instead when play cannot continue yet.
  Widget _bottom(Match match) {
    final state = match.state;
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    if (state.isComplete) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.result!.describe(match.setup),
            key: const Key('result'),
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(color: colors.runs),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.go(Routes.home),
            child: const Text('Back to matches'),
          ),
          TextButton(
            onPressed: match.canUndo ? _undo : null,
            child: const Text('Undo last ball'),
          ),
        ],
      );
    }
    final pending = state.pending;
    if (pending.isNotEmpty && pending.first is! ChooseBatter) {
      final q = pending.first;
      final previous = state.innings.length > 1 && q is ChooseOpeners
          ? state.innings[state.innings.length - 2]
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (previous != null) ...[
            Text(
              'Innings break',
              textAlign: TextAlign.center,
              style: text.titleLarge,
            ),
            Text(
              '${match.setup.team(previous.battingTeamId).name} '
              '${previous.runs}/${previous.wickets} (${oversLabel(previous)})',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted),
            ),
            if (chaseLine(state.currentInnings!) case final line?)
              Text(
                '${match.setup.team(state.currentInnings!.battingTeamId).name}: '
                '${line.toLowerCase()}',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.extras),
              ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            key: const Key('answerPending'),
            onPressed: () => _ask(match, force: true),
            child: Text(switch (q) {
              ChooseOpeners() =>
                previous == null ? 'Choose openers' : 'Start next innings',
              ChooseBowler(:final midOver) =>
                midOver ? 'Choose who finishes the over' : 'Choose bowler',
              ChooseFollowOn() => 'Decide the follow-on',
              ChooseBatter() => 'Choose next batter',
            }),
          ),
          TextButton(
            key: const Key('undoPending'),
            onPressed: match.canUndo ? _undo : null,
            child: const Text('Undo last ball'),
          ),
        ],
      );
    }
    return Keypad(
      armed: _armed,
      canUndo: match.canUndo,
      onRuns: _runs,
      onExtra: (e) => setState(() => _armed = _armed.toggle(e)),
      onWicket: () => _wicket(match),
      onUndo: _undo,
      onMore: () => _more(match),
    );
  }

  // ------------------------------------------------------------ actions

  Future<bool> _apply(MatchEvent event) async {
    try {
      await _controller.apply(event);
      return true;
    } on IllegalEventException catch (e) {
      _toast(e.message);
      return false;
    }
  }

  Future<void> _runs(int runs) async {
    final delivery = deliveryFor(_armed, runs);
    setState(() => _armed = ArmedExtra.none);
    if (await _apply(delivery)) {
      if (delivery.boundary != 0) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.selectionClick();
      }
    }
  }

  Future<void> _wicket(Match match) async {
    final inn = match.state.currentInnings!;
    final fielding = match.setup.team(inn.bowlingTeamId);
    final delivery = await showScoringSheet<Delivery>(
      context,
      WicketSheet(
        allowed: match.allowedDismissals(_armed.deliveryKind),
        armed: _armed,
        innings: inn,
        fielders: [for (final p in fielding.squad) p.id],
        nameOf: nameLookup(match.setup),
      ),
    );
    if (delivery == null || !mounted) return;
    setState(() => _armed = ArmedExtra.none);
    if (await _apply(delivery)) await HapticFeedback.heavyImpact();
  }

  Future<void> _undo() async {
    setState(() => _armed = ArmedExtra.none);
    _askedAt = null;
    await _controller.undoLastAction();
  }

  Future<void> _more(Match match) async {
    final inn = match.state.currentInnings!;
    final action = await showScoringSheet<MoreAction>(
      context,
      MoreSheet(canSwap: inn.strikerId != null && inn.nonStrikerId != null),
    );
    switch (action) {
      case MoreAction.fiveRuns:
        await _runs(5);
      case MoreAction.swapStrike:
        await _apply(const SwapStrike());
      case null:
        break;
    }
  }

  // ------------------------------------------- questions from the engine

  /// Answers or asks whatever the engine needs before the next ball.
  void _react(Match match) {
    if (!mounted || match.state.isComplete) return;
    final pending = match.state.pending;
    if (pending.isEmpty) return;
    final q = pending.first;
    if (q is ChooseBatter) {
      _autoBatter(match, q);
      return;
    }
    _ask(match);
  }

  /// The next batter in the order comes in at once; the scorer can change
  /// them from the message.
  Future<void> _autoBatter(Match match, ChooseBatter q) async {
    if (_asking) return;
    _asking = true;
    final ok = await _apply(BatterIn(q.suggested));
    _asking = false;
    if (!ok || !mounted) return;
    // A wicket off the last ball also needs a bowler: ask straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_match case final m?) _react(m);
    });
    final index = _match!.events.length - 1;
    final nameOf = nameLookup(match.setup);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${nameOf(q.suggested)} comes in'),
          action: SnackBarAction(
            label: 'Change',
            onPressed: () => _changeBatter(index, q, nameOf),
          ),
        ),
      );
  }

  Future<void> _changeBatter(int index, ChooseBatter q, NameOf nameOf) async {
    final chosen = await showScoringSheet<String>(
      context,
      BatterSheet(
        candidates: q.candidates,
        nameOf: nameOf,
        title: 'Who came in?',
      ),
    );
    if (chosen == null || chosen == q.suggested) return;
    try {
      await _controller.replaceAt(index, BatterIn(chosen));
    } on IllegalEventException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _ask(Match match, {bool force = false}) async {
    if (_asking) return;
    if (!force && _askedAt == match.events.length) return;
    final pending = match.state.pending;
    if (pending.isEmpty) return;
    _asking = true;
    _askedAt = match.events.length;
    final setup = match.setup;
    final inn = match.state.currentInnings!;
    final nameOf = nameLookup(setup);
    final Future<MatchEvent?> question = switch (pending.first) {
      final ChooseOpeners q => showScoringSheet<MatchEvent>(
        context,
        OpenersSheet(
          question: q,
          nameOf: nameOf,
          teamName: setup.team(q.battingTeamId).name,
          note: _breakNote(match),
        ),
      ),
      final ChooseBowler q => showScoringSheet<MatchEvent>(
        context,
        BowlerSheet(question: q, innings: inn, nameOf: nameOf),
      ),
      final ChooseFollowOn q => _followOn(q, setup),
      ChooseBatter() => Future.value(),
    };
    final event = await question;
    _asking = false;
    if (event != null && mounted) await _apply(event);
  }

  /// "Innings break · Team A 140/3 (20.0 ov) · Team B need 141 off 120
  /// balls", or null before the first innings.
  String? _breakNote(Match match) {
    final all = match.state.innings;
    if (all.length < 2) return null;
    final previous = all[all.length - 2];
    final next = all.last;
    final setup = match.setup;
    return [
      if (next.kind == InningsKind.superOver) 'Super over' else 'Innings break',
      '${setup.team(previous.battingTeamId).name} '
          '${previous.runs}/${previous.wickets} (${oversLabel(previous)})',
      if (chaseLine(next) case final line?)
        '${setup.team(next.battingTeamId).name} ${line.toLowerCase()}',
    ].join(' · ');
  }

  Future<MatchEvent?> _followOn(ChooseFollowOn q, MatchSetup setup) {
    final leader = setup.team(q.leadingTeamId).name;
    final trailer = setup.team(q.trailingTeamId).name;
    return showDialog<MatchEvent>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Follow-on'),
        content: Text('$leader lead by ${q.lead}. Make $trailer follow on?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const FollowOn(enforce: false)),
            child: Text('$leader bat again'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, const FollowOn(enforce: true)),
            child: const Text('Enforce'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
