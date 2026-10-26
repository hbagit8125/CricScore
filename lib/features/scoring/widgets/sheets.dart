import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
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
class BowlerSheet extends StatelessWidget {
  const BowlerSheet({
    super.key,
    required this.question,
    required this.innings,
    required this.nameOf,
  });

  final ChooseBowler question;
  final InningsState innings;
  final NameOf nameOf;

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
                  enabled: false,
                  title: Text(nameOf(e.key)),
                  subtitle: Text(switch (e.value) {
                    BowlerIneligibility.bowledPreviousOver =>
                      'Bowled the last over',
                    BowlerIneligibility.quotaReached => 'No overs left',
                    BowlerIneligibility.currentBowler => 'Bowling now',
                    BowlerIneligibility.bowledPreviousSuperOver =>
                      'Bowled the last super over',
                  }),
                ),
            ],
          ),
        ),
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

/// Less common actions for P3a. More arrive in P3b.
enum MoreAction { fiveRuns, swapStrike }

class MoreSheet extends StatelessWidget {
  const MoreSheet({super.key, required this.canSwap});

  final bool canSwap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _SheetTitle('More'),
      ListTile(
        key: const Key('more-5'),
        leading: const Icon(Icons.exposure_plus_1),
        title: const Text('5 runs'),
        subtitle: const Text('Five run, or with any extra armed'),
        onTap: () => Navigator.pop(context, MoreAction.fiveRuns),
      ),
      ListTile(
        key: const Key('more-swap'),
        enabled: canSwap,
        leading: const Icon(Icons.swap_vert),
        title: const Text('Swap strike'),
        subtitle: const Text('Correct which batter is on strike'),
        onTap: () => Navigator.pop(context, MoreAction.swapStrike),
      ),
      const SizedBox(height: 12),
    ],
  );
}
