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
    this.leftHanded = false,
  });

  final ArmedExtra armed;
  final ValueChanged<int> onRuns;
  final ValueChanged<ArmedExtra> onExtra;
  final VoidCallback onWicket;
  final VoidCallback onUndo;
  final VoidCallback onMore;
  final bool canUndo;

  /// Wicket and undo on the left, for scoring with the left thumb.
  final bool leftHanded;

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

    final actions = [
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
    ];
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
        _Row(
          leftHanded
              ? [...actions.reversed, runs(4), runs(6)]
              : [runs(4), runs(6), ...actions],
        ),
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
              backgroundColor: colors.key.withValues(alpha: colors.key.a * 0.6),
              side: BorderSide(color: colors.glassBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('More: retire, penalty, change bowler…'),
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

/// One key: frosted glass, or a glowing colour for 4, 6 and W. Sinks a
/// little under the thumb.
class _Key extends StatefulWidget {
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
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  var _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onTap != null;
    final fill = widget.fill;
    final base = (fill ?? colors.key).withValues(
      alpha: enabled ? (fill ?? colors.key).a : (fill ?? colors.key).a * 0.35,
    );
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: widget.semantics,
      enabled: enabled,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: fill == null ? Border.all(color: colors.glassBorder) : null,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                  Colors.white.withValues(alpha: colors.isGlass ? 0.10 : 0),
                  base,
                ),
                base,
              ],
            ),
            boxShadow: fill != null && enabled && colors.isGlass
                ? [
                    BoxShadow(
                      color: fill.withValues(alpha: _down ? 0.25 : 0.45),
                      blurRadius: _down ? 8 : 18,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: widget.onTap,
              onHighlightChanged: enabled ? _press : null,
              child: SizedBox(
                height: widget.small ? 50 : 62,
                child: Center(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: widget.small ? 19 : 28,
                      fontWeight: FontWeight.w700,
                      color: (widget.ink ?? colors.foreground).withValues(
                        alpha: enabled ? 1 : 0.45,
                      ),
                    ),
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
