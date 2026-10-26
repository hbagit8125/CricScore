import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../scoring_logic.dart';

/// The scoring keypad. Always on screen; one tap records an ordinary ball.
///
/// Extras arm first: Wd, Nb, B or LB light up, and the next runs key
/// records the extra with those runs. Tapping the lit key again disarms it.
class Keypad extends StatelessWidget {
  const Keypad({
    super.key,
    required this.armed,
    required this.onRuns,
    required this.onExtra,
    required this.onWicket,
    required this.onUndo,
    required this.onMore,
    required this.canUndo,
  });

  final ArmedExtra armed;
  final ValueChanged<int> onRuns;
  final ValueChanged<ArmedExtra> onExtra;
  final VoidCallback onWicket;
  final VoidCallback onUndo;
  final VoidCallback onMore;
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget runs(int n) => _Key(
      key: Key('runs$n'),
      label: armed == ArmedExtra.none && n == 0 ? '0' : '$n',
      semantics: _runsSemantics(n),
      onTap: (n == 6 && !armed.allowsSix) || (n == 0 && !armed.allowsZero)
          ? null
          : () => onRuns(n),
      fill: n == 4 || n == 6 ? colors.runs : null,
      ink: n == 4 || n == 6 ? colors.onSemantic : null,
    );
    Widget extra(String label, ArmedExtra e, String semantics) {
      final lit = switch (e) {
        ArmedExtra.byes =>
          armed == ArmedExtra.byes || armed == ArmedExtra.noBallByes,
        ArmedExtra.legByes =>
          armed == ArmedExtra.legByes || armed == ArmedExtra.noBallLegByes,
        ArmedExtra.noBall =>
          armed == ArmedExtra.noBall ||
              armed == ArmedExtra.noBallByes ||
              armed == ArmedExtra.noBallLegByes,
        _ => armed == e,
      };
      return _Key(
        key: Key('extra-${e.name}'),
        label: label,
        semantics: semantics,
        small: true,
        onTap: () => onExtra(e),
        fill: lit ? colors.extras : null,
        ink: lit ? colors.onSemantic : colors.extras,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (armed != ArmedExtra.none)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _armedHint(armed),
              key: const Key('armedHint'),
              style: TextStyle(
                color: colors.extras,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        _Row([runs(0), runs(1), runs(2), runs(3)]),
        _Row([
          runs(4),
          runs(6),
          _Key(
            key: const Key('wicket'),
            label: 'W',
            semantics: 'Wicket',
            onTap: onWicket,
            fill: colors.wicket,
            ink: colors.onSemantic,
          ),
          _Key(
            key: const Key('undo'),
            label: 'Undo',
            semantics: 'Undo last action',
            onTap: canUndo ? onUndo : null,
            small: true,
            ink: colors.muted,
          ),
        ]),
        _Row([
          extra('Wd', ArmedExtra.wide, 'Wide'),
          extra('Nb', ArmedExtra.noBall, 'No-ball'),
          extra('B', ArmedExtra.byes, 'Byes'),
          extra('LB', ArmedExtra.legByes, 'Leg byes'),
        ]),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton(
            key: const Key('more'),
            onPressed: onMore,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.muted,
              side: BorderSide(color: colors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('More: 5 runs · swap strike'),
          ),
        ),
      ],
    );
  }

  String _runsSemantics(int n) {
    final what = switch (armed) {
      ArmedExtra.none => n == 0 ? 'Dot ball' : '$n runs',
      ArmedExtra.wide => n == 4 ? 'Wide to the boundary' : 'Wide and $n run',
      ArmedExtra.noBall => 'No-ball and $n off the bat',
      ArmedExtra.byes => '$n byes',
      ArmedExtra.legByes => '$n leg byes',
      ArmedExtra.noBallByes => 'No-ball and $n byes',
      ArmedExtra.noBallLegByes => 'No-ball and $n leg byes',
    };
    return what;
  }

  static String _armedHint(ArmedExtra e) => switch (e) {
    ArmedExtra.wide => 'Wide: tap the runs taken (0 for none, 4 for boundary)',
    ArmedExtra.noBall => 'No-ball: tap the runs off the bat',
    ArmedExtra.byes => 'Byes: tap how many',
    ArmedExtra.legByes => 'Leg byes: tap how many',
    ArmedExtra.noBallByes => 'No-ball + byes: tap how many byes',
    ArmedExtra.noBallLegByes => 'No-ball + leg byes: tap how many',
    ArmedExtra.none => '',
  };
}

class _Row extends StatelessWidget {
  const _Row(this.keys);

  final List<Widget> keys;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: keys[i]),
        ],
      ],
    ),
  );
}

class _Key extends StatelessWidget {
  const _Key({
    super.key,
    required this.label,
    required this.semantics,
    required this.onTap,
    this.fill,
    this.ink,
    this.small = false,
  });

  final String label;
  final String semantics;
  final VoidCallback? onTap;
  final Color? fill;
  final Color? ink;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: semantics,
      enabled: enabled,
      excludeSemantics: true,
      child: Material(
        color: (fill ?? colors.key).withValues(alpha: enabled ? 1 : 0.35),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: small ? 48 : 60,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: small ? 18 : 26,
                  fontWeight: FontWeight.w700,
                  color: (ink ?? colors.foreground).withValues(
                    alpha: enabled ? 1 : 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
