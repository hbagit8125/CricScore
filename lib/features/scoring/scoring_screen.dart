import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/router.dart';
import '../../core/preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/glass.dart';
import '../../data/providers.dart';
import 'ball_edit.dart';
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

  /// The batter who just came in automatically, shown with a Change button
  /// until the next ball. Not a snackbar, which would cover the keypad.
  ({int index, ChooseBatter question})? _cameIn;

  /// The last celebration: FOUR!, SIX! or OUT!, replayed when [id] changes.
  ({int id, String text, Color color})? _burst;

  void _celebrate(String text, Color color) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    setState(
      () => _burst = (id: (_burst?.id ?? 0) + 1, text: text, color: color),
    );
  }

  MatchController get _controller =>
      ref.read(matchControllerProvider(widget.matchId).notifier);

  Match? get _match => ref.read(matchControllerProvider(widget.matchId)).value;

  @override
  void initState() {
    super.initState();
    _keepAwake(true);
  }

  @override
  void dispose() {
    _keepAwake(false);
    super.dispose();
  }

  /// The screen stays on while scoring. Not available everywhere (tests,
  /// some browsers), which is fine.
  static void _keepAwake(bool on) {
    try {
      WakelockPlus.toggle(enable: on).catchError((Object _) {});
    } on Object catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(matchControllerProvider(widget.matchId));
    ref.listen(matchControllerProvider(widget.matchId), (_, next) {
      if (next case AsyncData(:final value)) _react(value);
    });

    return switch (async) {
      AsyncData(:final value) => _scaffold(value),
      AsyncError(:final error) => GlassScaffold(
        appBar: AppBar(),
        body: Center(child: Text('This match could not be opened.\n$error')),
      ),
      _ => const GlassScaffold(body: SizedBox.shrink()),
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

    return GlassScaffold(
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
        actions: [
          IconButton(
            key: const Key('scorecard'),
            tooltip: 'Scorecard',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => context.push(Routes.scorecard(widget.matchId)),
          ),
        ],
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
                      GlassPanel(
                        tint: colors.runs,
                        radius: 26,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                        child: Stack(
                          children: [
                            ScoreHeader(innings: inn, setup: setup),
                            if (_burst case final b?)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: _Burst(
                                    key: ValueKey(b.id),
                                    text: b.text,
                                    color: b.color,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_cameIn case final c?) ...[
                        _CameInBanner(
                          name: nameOf(c.question.suggested),
                          onChange: () => _changeBatter(c.index, c.question),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (inn.batters.isNotEmpty) ...[
                        BattersPanel(innings: inn, nameOf: nameOf),
                        const SizedBox(height: 8),
                        BowlerPanel(innings: inn, nameOf: nameOf),
                        const SizedBox(height: 8),
                        GlassPanel(
                          radius: 18,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: OverStrip(
                            innings: inn,
                            rules: setup.rules,
                            onBallTap: (d) => _editBall(match, d),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GlassPanel(
                radius: 28,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: _bottom(match),
              ),
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
            key: const Key('resultScorecard'),
            onPressed: () => context.push(Routes.scorecard(widget.matchId)),
            child: const Text('Scorecard'),
          ),
          TextButton(
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
      leftHanded: ref.watch(preferencesProvider).value?.leftHanded ?? false,
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

  AppColors get _colors => context.colors;

  Future<bool> _apply(MatchEvent event) async {
    try {
      await _controller.apply(event);
      if (event is Delivery && _cameIn != null && mounted) {
        setState(() => _cameIn = null);
      }
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
      if (delivery.boundary != 0 && delivery.runsTo == RunsTo.batter) {
        _celebrate(delivery.boundary == 6 ? 'SIX!' : 'FOUR!', _colors.runs);
      }
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
    if (await _apply(delivery)) {
      _celebrate('OUT!', _colors.wicket);
      await HapticFeedback.heavyImpact();
    }
  }

  Future<void> _undo() async {
    setState(() {
      _armed = ArmedExtra.none;
      _cameIn = null;
    });
    _askedAt = null;
    await _controller.undoLastAction();
  }

  Future<void> _more(Match match) async {
    final inn = match.state.currentInnings!;
    final bothIn = inn.strikerId != null && inn.nonStrikerId != null;
    final midOver = inn.currentOver?.deliveries.isNotEmpty ?? false;
    final legalThisOver =
        inn.currentOver?.deliveries.where((d) => d.delivery.isLegal).length ??
        0;
    final action = await showScoringSheet<MoreAction>(
      context,
      MoreSheet(
        enabled: {
          MoreAction.fiveRuns,
          if (bothIn) MoreAction.swapStrike,
          if (inn.strikerId != null || inn.nonStrikerId != null)
            MoreAction.retire,
          if (_timedOutCandidate(match) != null) MoreAction.timedOut,
          if (bothIn && inn.bowlerId != null) MoreAction.runOutBackingUp,
          if (midOver && inn.bowlerId != null) MoreAction.changeBowler,
          if (legalThisOver > 0) MoreAction.overCalledEarly,
          MoreAction.penalty,
          if (match.setup.rules.ballsPerInnings != null)
            MoreAction.revisedTarget,
          MoreAction.renamePlayer,
          if (!inn.isClosed) MoreAction.endInnings,
          MoreAction.abandon,
        },
      ),
    );
    if (action == null || !mounted) return;
    final setup = match.setup;
    final nameOf = nameLookup(setup);
    switch (action) {
      case MoreAction.fiveRuns:
        await _runs(5);
      case MoreAction.swapStrike:
        await _apply(const SwapStrike());
      case MoreAction.retire:
        final event = await showScoringSheet<MatchEvent>(
          context,
          ChoiceSheet<MatchEvent>(
            title: 'Who is retiring?',
            subtitle: 'Retired hurt can come back later; retired out cannot',
            choices: [
              for (final id in [?inn.strikerId, ?inn.nonStrikerId]) ...[
                (
                  value: Retired(id, out: false),
                  label: '${nameOf(id)}: retired hurt',
                  detail: 'Not out; may bat again',
                  key: Key('retire-$id-hurt'),
                ),
                (
                  value: Retired(id, out: true),
                  label: '${nameOf(id)}: retired out',
                  detail: 'Counts as a wicket',
                  key: Key('retire-$id-out'),
                ),
              ],
            ],
          ),
        );
        if (event != null) await _apply(event);
      case MoreAction.timedOut:
        final index = _timedOutCandidate(match)!;
        final id = (match.events[index] as BatterIn).batterId;
        if (await _confirm(
          'Timed out?',
          '${nameOf(id)} was not ready in time and is out. The next batter '
              'comes in.',
          'Timed out',
        )) {
          await _replace(index, TimedOut(id));
        }
      case MoreAction.runOutBackingUp:
        final id = inn.nonStrikerId!;
        if (await _confirm(
          'Run out backing up?',
          '${nameOf(id)} left the crease before ${nameOf(inn.bowlerId!)} '
              'bowled and is run out. No ball is counted.',
          'Run out',
        )) {
          await _apply(RunOutBeforeDelivery(id));
        }
      case MoreAction.changeBowler:
        final event = await showScoringSheet<MatchEvent>(
          context,
          BowlerSheet(
            question: match.bowlerOptions(midOver: true),
            innings: inn,
            nameOf: nameOf,
          ),
        );
        if (event != null) await _apply(event);
      case MoreAction.overCalledEarly:
        final balls = legalThisOver == 1 ? '1 ball' : '$legalThisOver balls';
        if (await _confirm(
          'End the over now?',
          'The umpire called over after $balls. The over stands as called.',
          'End over',
        )) {
          await _apply(const OverCalledEarly());
        }
      case MoreAction.penalty:
        final event = await showScoringSheet<MatchEvent>(
          context,
          ChoiceSheet<MatchEvent>(
            title: 'Five penalty runs to',
            choices: [
              for (final team in [
                setup.team(inn.battingTeamId),
                setup.team(inn.bowlingTeamId),
              ])
                (
                  value: PenaltyRuns(teamId: team.id),
                  label: team.name,
                  detail: team.id == inn.battingTeamId
                      ? 'Batting side'
                      : 'Fielding side',
                  key: Key('penalty-${team.id}'),
                ),
            ],
          ),
        );
        if (event != null) await _apply(event);
      case MoreAction.revisedTarget:
        final event = await _revise(match);
        if (event != null) await _apply(event);
      case MoreAction.renamePlayer:
        await _rename(match);
      case MoreAction.endInnings:
        if (await _confirm(
          'End the innings?',
          'Use this when no one else is able to bat.',
          'End innings',
        )) {
          await _apply(const EndInnings());
        }
      case MoreAction.abandon:
        if (await _confirm(
          'Abandon the match?',
          'It will be recorded as no result. You can undo this.',
          'Abandon',
        )) {
          await _apply(const Abandoned());
        }
    }
  }

  /// The batter who has just come in and not yet faced, who may be timed
  /// out instead: the index of their [BatterIn] event.
  int? _timedOutCandidate(Match match) {
    final events = match.events;
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      if (e is BatterIn) return i;
      if (e is! BowlerSelected) return null;
    }
    return null;
  }

  Future<void> _replace(int index, MatchEvent event) async {
    try {
      await _controller.replaceAt(index, event);
    } on IllegalEventException catch (e) {
      _toast(e.message);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  /// Fewer overs, a new target, or both, as the officials set them.
  Future<RevisedTarget?> _revise(Match match) {
    final inn = match.state.currentInnings!;
    final rules = match.setup.rules;
    final chasing = inn.target != null || match.state.innings.length > 1;
    final limit = inn.ballLimit;
    final overs = TextEditingController(
      text: limit == null ? '' : oversText(limit, rules.ballsPerOver),
    );
    final target = TextEditingController();
    return showDialog<RevisedTarget>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Reduce overs or revise target'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('revisedOvers'),
                  controller: overs,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Overs in this innings',
                  ),
                ),
                if (chasing)
                  TextField(
                    key: const Key('revisedTarget'),
                    controller: target,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Target (runs to win)',
                      helperText: 'From the officials, e.g. by DLS',
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(color: context.colors.wicket),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('saveRevision'),
                onPressed: () {
                  final balls = parseOvers(overs.text, rules.ballsPerOver);
                  final runs = int.tryParse(target.text.trim());
                  final newBalls = balls == limit ? null : balls;
                  if (newBalls == null && runs == null) {
                    setState(() => error = 'Enter the new overs or target.');
                    return;
                  }
                  Navigator.pop(
                    context,
                    RevisedTarget(ballsPerInnings: newBalls, target: runs),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _rename(Match match) async {
    final setup = match.setup;
    final id = await showScoringSheet<String>(
      context,
      ChoiceSheet<String>(
        title: 'Rename a player',
        choices: [
          for (final team in [setup.teamA, setup.teamB])
            for (final p in team.squad)
              (
                value: p.id,
                label: p.name,
                detail: team.name,
                key: Key('rename-${p.id}'),
              ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    final controller = TextEditingController(text: nameLookup(setup)(id));
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          key: const Key('newName'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('saveName'),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await _controller.renamePlayer(id, name);
    } on IllegalEventException catch (e) {
      _toast(e.message);
    }
  }

  /// Opens a recorded ball for correction and replays the match with it.
  Future<void> _editBall(Match match, DeliveryRecord ball) async {
    final edit = await showScoringSheet<BallEdit>(
      context,
      EditBallSheet(
        ball: ball,
        label: ballLabel(ball.delivery, match.setup.rules),
        title: ballPosition(match, ball),
        nameOf: nameLookup(match.setup),
      ),
    );
    if (edit == null || !mounted) return;
    final fixed = correctedLog(match, ball, edit);
    try {
      await _controller.replaceEvents(fixed.events);
      _toast(fixed.note ?? 'Ball corrected');
    } on IllegalEventException catch (e) {
      _toast('That change does not fit what happened later: ${e.message}');
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
    setState(() => _cameIn = (index: _match!.events.length - 1, question: q));
  }

  Future<void> _changeBatter(int index, ChooseBatter q) async {
    final nameOf = nameLookup(_match!.setup);
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
      if (mounted) {
        setState(
          () => _cameIn = (
            index: index,
            question: ChooseBatter(
              battingTeamId: q.battingTeamId,
              candidates: q.candidates,
              suggested: chosen,
              atStrikersEnd: q.atStrikersEnd,
            ),
          ),
        );
      }
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
        BowlerSheet(
          question: q,
          innings: inn,
          nameOf: nameOf,
          // Straight after an over, the umpire may have allowed one more.
          canExtend:
              !q.midOver &&
              inn.overs.isNotEmpty &&
              inn.overs.last.isComplete &&
              match.events.isNotEmpty &&
              match.events.last is! OverCalledEarly,
        ),
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

class _CameInBanner extends StatelessWidget {
  const _CameInBanner({required this.name, required this.onChange});

  final String name;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const Key('cameIn'),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: colors.runs.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.login, size: 18, color: colors.runs),
          const SizedBox(width: 8),
          Expanded(child: Text('$name comes in')),
          TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
}

/// A big word that springs up and fades: FOUR!, SIX! or OUT!.
class _Burst extends StatelessWidget {
  const _Burst({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 1200),
    builder: (context, t, _) {
      if (t >= 1) return const SizedBox.shrink();
      final grow = Curves.easeOutBack.transform((t / 0.35).clamp(0, 1));
      final fade = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
      return Align(
        alignment: Alignment.centerRight,
        child: Opacity(
          opacity: fade.clamp(0, 1),
          child: Transform.scale(
            scale: 0.5 + 0.5 * grow,
            child: Text(
              text,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 46,
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
                letterSpacing: 1,
                color: color,
                shadows: [
                  Shadow(color: color.withValues(alpha: 0.7), blurRadius: 28),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
