import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The glowing background every screen sits on: a gradient with soft pools
/// of light, like floodlights on a night pitch. Static, so glass over it
/// costs one blur per frame at most.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final backdrop = colors.backdrop;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: backdrop.length < 2
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: backdrop,
              ),
        color: backdrop.length < 2 ? colors.background : null,
      ),
      child: colors.glows.isEmpty
          ? const SizedBox.expand()
          : CustomPaint(
              painter: _GlowPainter(colors.glows),
              size: Size.infinite,
            ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.glows);

  final List<Color> glows;

  // Where each pool of light sits, as fractions of the screen, and its
  // radius as a fraction of the longer side.
  static const _spots = [
    (Offset(0.05, 0.02), 0.62),
    (Offset(1.0, 0.38), 0.55),
    (Offset(0.15, 1.0), 0.6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final longest = size.longestSide;
    for (var i = 0; i < glows.length && i < _spots.length; i++) {
      final (at, r) = _spots[i];
      final centre = Offset(at.dx * size.width, at.dy * size.height);
      final radius = r * longest;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [glows[i], glows[i].withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.glows != glows;
}

/// A [Scaffold] on the app backdrop. Each screen paints its own backdrop
/// so pages never show through each other during transitions.
class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(child: AppBackdrop()),
      // Glass on this screen shares one backdrop pass.
      BackdropGroup(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          body: body,
          bottomNavigationBar: bottomNavigationBar,
        ),
      ),
    ],
  );
}

/// Frosted glass: blurs what is behind it, with a faint top-left sheen
/// and a light edge. Solid with a dark edge in the outdoor theme.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.tint,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// A colour washed into the glass, for a panel that should stand out.
  final Color? tint;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shape = BorderRadius.circular(radius);
    final base = tint == null
        ? colors.surface
        : Color.alphaBlend(tint!.withValues(alpha: 0.16), colors.surface);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null || onLongPress != null) {
      content = InkWell(
        borderRadius: shape,
        onTap: onTap,
        onLongPress: onLongPress,
        child: content,
      );
    }
    // Ink from list tiles and buttons inside lands on the glass.
    content = Material(type: MaterialType.transparency, child: content);
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(
          color: colors.glassBorder,
          width: colors.isGlass ? 1 : 1.5,
        ),
        color: colors.isGlass ? null : base,
        gradient: colors.isGlass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(Colors.white.withValues(alpha: 0.06), base),
                  base,
                ],
              )
            : null,
      ),
      child: content,
    );
    if (!colors.isGlass) return decorated;
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter.grouped(
        filter: ImageFilter.blur(sigmaX: colors.blur, sigmaY: colors.blur),
        child: decorated,
      ),
    );
  }
}

/// A bottom sheet of glass, for every sheet in the app.
Future<T?> showGlassSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) {
        final colors = context.colors;
        const shape = BorderRadius.vertical(top: Radius.circular(28));
        return ClipRRect(
          borderRadius: shape,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: colors.blur * 1.4,
              sigmaY: colors.blur * 1.4,
            ),
            child: Material(
              color: colors.sheet,
              shape: RoundedRectangleBorder(
                borderRadius: shape,
                side: BorderSide(color: colors.glassBorder),
              ),
              child: SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 10, bottom: 14),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.muted.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Flexible(child: child),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

/// A small uppercase label above a group of content.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? const EdgeInsets.only(top: 20, bottom: 8, left: 4),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: context.colors.muted,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// The app mark: a glowing green disc with a cricket bat and ball.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.runs,
            Color.lerp(colors.runs, const Color(0xFF1B8FB0), 0.55)!,
          ],
        ),
        boxShadow: colors.isGlass
            ? [
                BoxShadow(
                  color: colors.runs.withValues(alpha: 0.5),
                  blurRadius: size * 0.5,
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.sports_cricket,
        size: size * 0.55,
        color: colors.onSemantic,
      ),
    );
  }
}
