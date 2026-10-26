import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../scoring_logic.dart';

/// Looks up player names across both squads.
typedef NameOf = String Function(String playerId);

NameOf nameLookup(MatchSetup setup) {
  final names = {
    for (final p in [...setup.teamA.squad, ...setup.teamB.squad]) p.id: p.name,
  };
  return (id) => names[id] ?? '?';
}

/// Team, score and overs in large condensed numerals, with the chase or
/// run rate underneath.
class ScoreHeader extends StatelessWidget {
  const ScoreHeader({super.key, required this.innings, required this.setup});

  final InningsState innings;
  final MatchSetup setup;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final inn = innings;
    final chase = chaseLine(inn);
    final rrr = inn.requiredRunRate;
    final details = [
      ?chase,
      if (rrr != null) 'RRR ${rrr.toStringAsFixed(2)}',
      'CRR ${inn.runRate.toStringAsFixed(2)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              setup.team(inn.battingTeamId).name.toUpperCase(),
              style: text.labelLarge?.copyWith(
                color: colors.muted,
                letterSpacing: 1.2,
              ),
            ),
            if (inn.kind == InningsKind.superOver) ...[
              const SizedBox(width: 8),
              _Tag('Super over', color: colors.extras),
            ],
            if (inn.freeHitNext) ...[
              const SizedBox(width: 8),
              _Tag('Free hit', color: colors.extras),
            ],
          ],
        ),
        // Shrinks rather than overflows on narrow screens or large text.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text(
                  '${inn.runs}/${inn.wickets}',
                  key: const Key('score'),
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ).copyWith(color: colors.foreground),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                oversLabel(inn),
                key: const Key('overs'),
                maxLines: 1,
                style: text.titleLarge?.copyWith(color: colors.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          details.join(' · '),
          style: text.bodyMedium?.copyWith(
            color: chase != null ? colors.extras : colors.muted,
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// The two batters, striker marked, and their partnership.
class BattersPanel extends StatelessWidget {
  const BattersPanel({super.key, required this.innings, required this.nameOf});

  final InningsState innings;
  final NameOf nameOf;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final inn = innings;
    Widget row(String? id, {required bool striker}) {
      if (id == null) {
        return _Line(
          left: Text('—', style: TextStyle(color: colors.muted)),
          right: const SizedBox.shrink(),
        );
      }
      final b = inn.batter(id);
      return _Line(
        left: Row(
          children: [
            SizedBox(
              width: 16,
              child: striker
                  ? Icon(Icons.circle, size: 8, color: colors.runs)
                  : null,
            ),
            Flexible(
              child: Text(
                nameOf(id),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: striker ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        right: Text(
          '${b?.runs ?? 0} (${b?.balls ?? 0})',
          style: const TextStyle(
            fontFeatures: [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final p = inn.partnerships.isEmpty ? null : inn.partnerships.last;
    return _Card(
      children: [
        row(inn.strikerId, striker: true),
        row(inn.nonStrikerId, striker: false),
        if (p != null)
          _Line(
            left: Text('Partnership', style: TextStyle(color: colors.muted)),
            right: Text(
              '${p.runs} (${p.balls})',
              style: TextStyle(color: colors.muted),
            ),
          ),
      ],
    );
  }
}

/// Current bowler and their figures.
class BowlerPanel extends StatelessWidget {
  const BowlerPanel({super.key, required this.innings, required this.nameOf});

  final InningsState innings;
  final NameOf nameOf;

  @override
  Widget build(BuildContext context) {
    final inn = innings;
    final over = inn.currentOver;
    final id = inn.bowlerId ?? over?.bowlerIds.last;
    if (id == null) return const SizedBox.shrink();
    final card = inn.bowler(id);
    return _Card(
      children: [
        _Line(
          left: Text(
            nameOf(id),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          right: Text(
            card?.figures(inn.ballsPerOver) ?? '0.0-0-0-0',
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// The balls of the over in progress, or of the last over between overs.
class OverStrip extends StatelessWidget {
  const OverStrip({super.key, required this.innings, required this.rules});

  final InningsState innings;
  final MatchRules rules;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final overs = innings.overs.where((o) => o.deliveries.isNotEmpty);
    final over = innings.currentOver ?? (overs.isEmpty ? null : overs.last);
    final balls = over?.deliveries ?? const <DeliveryRecord>[];
    final legal = balls.where((d) => d.delivery.isLegal).length;
    final empty = over == null || over.isComplete
        ? 0
        : (rules.ballsPerOver - legal).clamp(0, rules.ballsPerOver);
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            over == null
                ? 'This over'
                : over.isComplete
                ? 'Over ${over.number}'
                : 'This over',
            style: TextStyle(color: colors.muted),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in balls) _BallChip(record: d, rules: rules),
              for (var i = 0; i < empty; i++) const _BallChip(),
            ],
          ),
        ),
      ],
    );
  }
}

class _BallChip extends StatelessWidget {
  const _BallChip({this.record, this.rules});

  final DeliveryRecord? record;
  final MatchRules? rules;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final d = record?.delivery;
    if (d == null) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.line),
        ),
      );
    }
    final wicket = d.dismissal != null;
    final boundary = d.boundary != 0 && d.runsTo == RunsTo.batter;
    final extra = d.kind != DeliveryKind.legal || d.runsTo != RunsTo.batter;
    final bg = wicket
        ? colors.wicket
        : boundary
        ? colors.runs
        : colors.key;
    final fg = wicket || boundary
        ? colors.onSemantic
        : extra
        ? colors.extras
        : colors.foreground;
    return Container(
      constraints: const BoxConstraints(minWidth: 30),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
      ),
      // widthFactor keeps the chip as narrow as its label.
      child: Center(
        widthFactor: 1,
        child: Text(
          ballLabel(d, rules!),
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          children[i],
        ],
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: left),
      const SizedBox(width: 12),
      right,
    ],
  );
}
