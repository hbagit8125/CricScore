import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../ball_edit.dart';
import '../scoring_logic.dart';
import 'score_panels.dart';

Future<T?> showScoringSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colors.surface,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: child,
        ),
      ),
    );

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (subtitle != null)
          Text(subtitle!, style: TextStyle(color: context.colors.muted)),
      ],
    ),
  );
}

/// Opening pair, pre-selected; "Start innings" is one tap.
class OpenersSheet extends StatefulWidget {
  const OpenersSheet({
    super.key,
    required this.question,
    required this.nameOf,
    required this.teamName,
    this.note,
  });

  final ChooseOpeners question;
  final NameOf nameOf;
  final String teamName;

  /// The innings break summary, when this is not the first innings.
  final String? note;

  @override
  State<OpenersSheet> createState() => _OpenersSheetState();
}

class _OpenersSheetState extends State<OpenersSheet> {
  late String _striker = widget.question.suggestedStriker;
  late String _nonStriker = widget.question.suggestedNonStriker;

  /// Tapping a player puts them on strike; the previous striker moves to
  /// the other end.
  void _pick(String id) => setState(() {
    if (id == _striker) return;
    _nonStriker = _striker;
    _striker = id;
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              widget.note!,
              key: const Key('inningsBreak'),
              style: TextStyle(
                color: colors.extras,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        _SheetTitle(
          '${widget.teamName} openers',
          subtitle: 'Tap a player to put them on strike',
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final id in widget.question.candidates)
                ListTile(
                  key: Key('opener-$id'),
                  title: Text(widget.nameOf(id)),
                  trailing: id == _striker
                      ? Text('On strike', style: TextStyle(color: colors.runs))
                      : id == _nonStriker
                      ? Text('Other end', style: TextStyle(color: colors.muted))
                      : null,
                  onTap: () => _pick(id),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const Key('startInnings'),
            onPressed: () => Navigator.pop(
              context,
              OpenersSelected(strikerId: _striker, nonStrikerId: _nonStriker),
            ),
            child: const Text('Start innings'),
          ),
        ),
      ],
    );
  }
}

/// Who bowls next: the suggested bowler first, ineligible bowlers greyed
/// with the reason. One tap.
///
/// An ineligible bowler can still be chosen when the umpire allowed it,
/// after a confirmation. With [canExtend], the scorer can instead record
/// that the umpire gave one more ball in the over just finished.
class BowlerSheet extends StatelessWidget {
  const BowlerSheet({
    super.key,
    required this.question,
    required this.innings,
    required this.nameOf,
    this.canExtend = false,
  });

  final ChooseBowler question;
  final InningsState innings;
  final NameOf nameOf;
  final bool canExtend;

  static String reason(BowlerIneligibility r) => switch (r) {
    BowlerIneligibility.bowledPreviousOver => 'Bowled the last over',
    BowlerIneligibility.quotaReached => 'No overs left',
    BowlerIneligibility.currentBowler => 'Bowling now',
    BowlerIneligibility.bowledPreviousSuperOver => 'Bowled the last super over',
  };

  Future<void> _override(
    BuildContext context,
    String id,
    BowlerIneligibility why,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Let ${nameOf(id)} bowl?'),
        content: Text(
          'The records say: ${reason(why).toLowerCase()}. Record it anyway '
          'because the umpire allowed it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('umpireAllowed'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Umpire allowed it'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.pop(context, BowlerSelected(id, umpireAllowed: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final q = question;
    final order = [
      ?q.suggested,
      for (final id in q.eligible)
        if (id != q.suggested) id,
    ];
    String figures(String id) =>
        innings.bowler(id)?.figures(innings.ballsPerOver) ?? 'Not bowled yet';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle(
          q.midOver ? 'Who finishes the over?' : 'Next bowler',
          subtitle: q.eligible.isEmpty ? 'Nobody is eligible to bowl.' : null,
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final id in order)
                ListTile(
                  key: Key('bowler-$id'),
                  tileColor: id == q.suggested
                      ? colors.runs.withValues(alpha: 0.12)
                      : null,
                  title: Text(nameOf(id)),
                  subtitle: Text(figures(id)),
                  trailing: id == q.suggested
                      ? Text('Suggested', style: TextStyle(color: colors.runs))
                      : null,
                  onTap: () => Navigator.pop(context, BowlerSelected(id)),
                ),
              for (final e in q.ineligible.entries)
                ListTile(
                  key: Key('bowler-${e.key}'),
                  title: Text(
                    nameOf(e.key),
                    style: TextStyle(color: colors.muted),
                  ),
                  subtitle: Text(reason(e.value)),
                  trailing: e.value == BowlerIneligibility.currentBowler
                      ? null
                      : Icon(Icons.gavel, size: 18, color: colors.muted),
                  onTap: e.value == BowlerIneligibility.currentBowler
                      ? null
                      : () => _override(context, e.key, e.value),
                ),
            ],
          ),
        ),
        if (canExtend)
          TextButton.icon(
            key: const Key('overExtended'),
            onPressed: () => Navigator.pop(context, const OverExtended()),
            icon: const Icon(Icons.add),
            label: const Text('Umpire allowed another ball in that over'),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Choose a batter: next in, or a correction to the one who came in.
class BatterSheet extends StatelessWidget {
  const BatterSheet({
    super.key,
    required this.candidates,
    required this.nameOf,
    required this.title,
  });

  final List<String> candidates;
  final NameOf nameOf;
  final String title;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SheetTitle(title),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final id in candidates)
              ListTile(
                key: Key('batter-$id'),
                title: Text(nameOf(id)),
                onTap: () => Navigator.pop(context, id),
              ),
          ],
        ),
      ),
    ],
  );
}

/// How the batter was out, in as few taps as the dismissal needs.
///
/// Bowled, LBW and hit wicket finish in one tap. Caught and stumped ask
/// for the fielder (skippable). Run out asks which batter and how many
/// runs were completed. Dismissals the Laws rule out for this delivery are
/// shown but disabled.
class WicketSheet extends StatefulWidget {
  const WicketSheet({
    super.key,
    required this.allowed,
    required this.armed,
    required this.innings,
    required this.fielders,
    required this.nameOf,
  });

  final Set<DismissalKind> allowed;
  final ArmedExtra armed;
  final InningsState innings;
  final List<String> fielders;
  final NameOf nameOf;

  @override
  State<WicketSheet> createState() => _WicketSheetState();
}

class _WicketSheetState extends State<WicketSheet> {
  DismissalKind? _kind;
  String? _batter;

  static const _main = [
    DismissalKind.caught,
    DismissalKind.bowled,
    DismissalKind.lbw,
    DismissalKind.runOut,
    DismissalKind.stumped,
    DismissalKind.hitWicket,
  ];
  static const _other = [
    DismissalKind.obstructingTheField,
    DismissalKind.hitTheBallTwice,
  ];

  String get _striker => widget.innings.strikerId!;

  void _finish({String? fielder, int runs = 0, String? batter}) {
    final kind = _kind!;
    final dismissal = Dismissal(
      kind: kind,
      batterId: batter ?? _batter ?? _striker,
      fielderId: fielder,
    );
    Navigator.pop(
      context,
      deliveryFor(widget.armed, runs, dismissal: dismissal),
    );
  }

  void _choose(DismissalKind k) {
    setState(() => _kind = k);
    if (k.strikerOnly &&
        k != DismissalKind.caught &&
        k != DismissalKind.stumped) {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final nonStriker = widget.innings.nonStrikerId;
    if (kind == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle(
            'How was ${widget.nameOf(_striker)} out?',
            subtitle: widget.armed == ArmedExtra.none
                ? (widget.innings.freeHitNext ? 'Free hit' : null)
                : 'On a ${switch (widget.armed.deliveryKind) {
                    DeliveryKind.wide => 'wide',
                    DeliveryKind.noBall => 'no-ball',
                    DeliveryKind.legal => 'delivery',
                  }}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final k in [..._main, ..._other])
                  if (_main.contains(k) || widget.allowed.contains(k))
                    _Choice(
                      key: Key('out-${k.name}'),
                      label: dismissalName(k),
                      onTap: widget.allowed.contains(k)
                          ? () => _choose(k)
                          : null,
                    ),
              ],
            ),
          ),
        ],
      );
    }

    // Run out and obstructing: which batter?
    if (!kind.strikerOnly && _batter == null && nonStriker != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle('${dismissalName(kind)}: who is out?'),
          for (final id in [_striker, nonStriker])
            ListTile(
              key: Key('outBatter-$id'),
              title: Text(widget.nameOf(id)),
              subtitle: Text(id == _striker ? 'Striker' : 'Non-striker'),
              onTap: () => setState(() => _batter = id),
            ),
          const SizedBox(height: 12),
        ],
      );
    }

    if (kind == DismissalKind.runOut ||
        kind == DismissalKind.obstructingTheField) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetTitle('Runs completed before the wicket'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                for (final r in [0, 1, 2, 3]) ...[
                  if (r > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _Choice(
                      key: Key('completed-$r'),
                      label: '$r',
                      onTap: () => _finish(runs: r, batter: _batter),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    // Caught or stumped: the fielder, which can be skipped.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetTitle(
          kind == DismissalKind.caught ? 'Caught by' : 'Stumped by',
          subtitle: 'Optional',
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                key: const Key('fielder-skip'),
                title: const Text('Skip'),
                onTap: _finish,
              ),
              for (final id in widget.fielders)
                ListTile(
                  key: Key('fielder-$id'),
                  title: Text(widget.nameOf(id)),
                  onTap: () => _finish(fielder: id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.key.withValues(alpha: onTap == null ? 0.35 : 1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: colors.foreground.withValues(
                  alpha: onTap == null ? 0.45 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Less common actions, grouped as a scorer thinks of them.
enum MoreAction {
  fiveRuns,
  swapStrike,
  retire,
  timedOut,
  runOutBackingUp,
  changeBowler,
  overCalledEarly,
  penalty,
  revisedTarget,
  renamePlayer,
  endInnings,
  abandon,
}

class MoreSheet extends StatelessWidget {
  const MoreSheet({super.key, required this.enabled});

  /// Actions that make sense right now; the rest are shown disabled.
  final Set<MoreAction> enabled;

  @override
  Widget build(BuildContext context) {
    Widget item(MoreAction a, IconData icon, String title, String subtitle) =>
        ListTile(
          key: Key('more-${a.name}'),
          enabled: enabled.contains(a),
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: () => Navigator.pop(context, a),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetTitle('More'),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              const _Group('Batting'),
              item(
                MoreAction.fiveRuns,
                Icons.exposure_plus_1,
                '5 runs',
                'Five run, or with any extra armed',
              ),
              item(
                MoreAction.swapStrike,
                Icons.swap_vert,
                'Swap strike',
                'Correct which batter is on strike',
              ),
              item(
                MoreAction.retire,
                Icons.healing,
                'Retire a batter',
                'Retired hurt (not out) or retired out',
              ),
              item(
                MoreAction.timedOut,
                Icons.timer_off_outlined,
                'Timed out',
                'The new batter was not ready in time',
              ),
              item(
                MoreAction.runOutBackingUp,
                Icons.directions_run,
                'Non-striker run out backing up',
                'Run out by the bowler before the ball',
              ),
              const _Group('Bowling and umpires'),
              item(
                MoreAction.changeBowler,
                Icons.person_remove_outlined,
                'Change bowler mid-over',
                'The bowler cannot finish the over',
              ),
              item(
                MoreAction.overCalledEarly,
                Icons.gavel,
                'Umpire called over early',
                'The over stands as called',
              ),
              item(
                MoreAction.penalty,
                Icons.flag_outlined,
                'Penalty runs',
                'Five runs awarded to either side',
              ),
              const _Group('Match'),
              item(
                MoreAction.revisedTarget,
                Icons.cloud_outlined,
                'Reduce overs or revise target',
                'After rain or a delay',
              ),
              item(
                MoreAction.renamePlayer,
                Icons.edit_outlined,
                'Rename a player',
                'Fix a spelling; the scoring is unchanged',
              ),
              item(
                MoreAction.endInnings,
                Icons.stop_circle_outlined,
                'End innings',
                'No one else is able to bat',
              ),
              item(
                MoreAction.abandon,
                Icons.block,
                'Abandon match',
                'No result',
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: context.colors.muted,
        letterSpacing: 1.2,
      ),
    ),
  );
}

typedef Choice<T> = ({T value, String label, String? detail, Key? key});

/// One choice from a short list, for example which batter retires.
class ChoiceSheet<T> extends StatelessWidget {
  const ChoiceSheet({
    super.key,
    required this.title,
    required this.choices,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Choice<T>> choices;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SheetTitle(title, subtitle: subtitle),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in choices)
              ListTile(
                key: c.key,
                title: Text(c.label),
                subtitle: c.detail == null ? null : Text(c.detail!),
                onTap: () => Navigator.pop(context, c.value),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ],
  );
}

/// Corrects a ball already recorded: change what happened, add a ball the
/// scorer missed before it, or remove it.
class EditBallSheet extends StatefulWidget {
  const EditBallSheet({
    super.key,
    required this.ball,
    required this.label,
    required this.title,
    required this.nameOf,
  });

  final DeliveryRecord ball;

  /// The ball as shown in the over strip, e.g. `2wd`.
  final String label;

  /// "Over 4, ball 3".
  final String title;
  final NameOf nameOf;

  @override
  State<EditBallSheet> createState() => _EditBallSheetState();
}

class _EditBallSheetState extends State<EditBallSheet> {
  var _insert = false;
  late var _extra = _armedFor(widget.ball.delivery);
  late var _keepWicket = widget.ball.delivery.dismissal != null;

  static ArmedExtra _armedFor(Delivery d) => switch ((d.kind, d.runsTo)) {
    (DeliveryKind.wide, _) => ArmedExtra.wide,
    (DeliveryKind.noBall, RunsTo.byes) => ArmedExtra.noBallByes,
    (DeliveryKind.noBall, RunsTo.legByes) => ArmedExtra.noBallLegByes,
    (DeliveryKind.noBall, _) => ArmedExtra.noBall,
    (_, RunsTo.byes) => ArmedExtra.byes,
    (_, RunsTo.legByes) => ArmedExtra.legByes,
    _ => ArmedExtra.none,
  };

  void _pick(int runs) {
    final wicket = !_insert && _keepWicket
        ? widget.ball.delivery.dismissal
        : null;
    final d = deliveryFor(_extra, runs, dismissal: wicket);
    Navigator.pop(
      context,
      _insert ? BallEdit.insertBefore(d) : BallEdit.change(d),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dismissal = widget.ball.delivery.dismissal;
    const extras = [
      (ArmedExtra.none, 'Off bat'),
      (ArmedExtra.wide, 'Wd'),
      (ArmedExtra.noBall, 'Nb'),
      (ArmedExtra.byes, 'B'),
      (ArmedExtra.legByes, 'LB'),
    ];
    final selected = switch (_extra) {
      ArmedExtra.noBallByes || ArmedExtra.noBallLegByes => ArmedExtra.noBall,
      final e => e,
    };
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SheetTitle(
            widget.title,
            subtitle:
                'Recorded as ${widget.label} to '
                '${widget.nameOf(widget.ball.strikerId)}',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Change it')),
                ButtonSegment(
                  value: true,
                  label: Text('Add a missed ball before'),
                ),
              ],
              selected: {_insert},
              onSelectionChanged: (v) => setState(() => _insert = v.single),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (e, label) in extras)
                  ChoiceChip(
                    key: Key('edit-extra-${e.name}'),
                    label: Text(label),
                    selected: selected == e,
                    onSelected: (_) => setState(() => _extra = e),
                  ),
              ],
            ),
          ),
          if (!_insert && dismissal != null)
            SwitchListTile(
              key: const Key('keepWicket'),
              title: Text('Keep the wicket (${dismissalName(dismissal.kind)})'),
              value: _keepWicket,
              onChanged: (v) => setState(() => _keepWicket = v),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                for (final r in [0, 1, 2, 3, 4, 5, 6]) ...[
                  if (r > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _Choice(
                      key: Key('edit-runs$r'),
                      label: '$r',
                      onTap:
                          (r == 6 && !_extra.allowsSix) ||
                              (r == 0 && !_extra.allowsZero)
                          ? null
                          : () => _pick(r),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_insert)
            TextButton.icon(
              key: const Key('removeBall'),
              onPressed: () => Navigator.pop(context, const BallEdit.remove()),
              icon: Icon(Icons.delete_outline, color: colors.wicket),
              label: Text(
                'Remove this ball',
                style: TextStyle(color: colors.wicket),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
