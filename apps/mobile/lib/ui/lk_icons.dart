// The interface icons (apps/web/app/ui/Icon.tsx, from docs/design/system/project/icons/icons.json:
// lk_icon_shapes.dart) and the web's other inline SVG icons: the fingerprint (apps/web/app/ui/FingerprintIcon.tsx) and the moon and
// the sun of the day/night switch (apps/web/app/ui/ThemeToggle.tsx). Each is 22px, drawn from a 24px
// viewBox in the colour of the text around it (`currentColor`).
import 'package:flutter/widgets.dart';

import 'lk_icon_shapes.dart';
import 'svg_path.dart';

export 'lk_icon_shapes.dart' show LkIconName, LkIconVariant;

/// An icon of the web: [paths] in a 24 x 24 box, scaled to [size].
class _SvgIcon extends StatelessWidget {
  const _SvgIcon({
    required this.paths,
    required this.fill,
    required this.strokeWidth,
    this.filledShapes = const [],
  });

  final List<Path> paths;

  /// Whether [paths] are filled (the moon) or only stroked (the fingerprint, the sun's rays).
  final bool fill;

  /// In viewBox units; zero for no stroke.
  final double strokeWidth;

  /// Shapes that are filled whatever [fill] says (the sun's disc).
  final List<Path> filledShapes;

  @override
  Widget build(BuildContext context) {
    // `currentColor`: the text colour around the icon.
    final colour = DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    return ExcludeSemantics(
      child: CustomPaint(
        size: const Size.square(22),
        painter: _SvgPainter(paths, filledShapes, fill, strokeWidth, colour),
      ),
    );
  }
}

class _SvgPainter extends CustomPainter {
  const _SvgPainter(this.paths, this.filledShapes, this.fill, this.strokeWidth, this.color);

  final List<Path> paths;
  final List<Path> filledShapes;
  final bool fill;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final solid = Paint()
      ..style = PaintingStyle.fill
      ..color = color
      ..isAntiAlias = true;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;
    for (final shape in filledShapes) {
      canvas.drawPath(shape, solid);
    }
    for (final path in paths) {
      if (fill) canvas.drawPath(path, solid);
      if (strokeWidth > 0) canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_SvgPainter old) =>
      old.color != color ||
      old.fill != fill ||
      old.strokeWidth != strokeWidth ||
      old.paths != paths ||
      old.filledShapes != filledShapes;
}

final _fingerprint = [
  for (final d in const [
    'M12 11v3a8 8 0 0 1-1.2 4.2',
    'M8.5 12a3.5 3.5 0 0 1 7 0v1.5a11 11 0 0 1-.9 4.4',
    'M5.3 15.5A9.6 9.6 0 0 0 5.5 12a6.5 6.5 0 0 1 11.6-4',
    'M18.4 11a6.5 6.5 0 0 1 .1 1.5c0 2.6-.4 5-1.2 7',
    'M4.3 7.6A9.5 9.5 0 0 1 12 3.5a9.5 9.5 0 0 1 3.4.6',
    'M8.9 19.8c.6-1.5 1-3.1 1.1-4.8',
  ])
    parseSvgPath(d),
];

/// The fingerprint of the passkey buttons (sign-in, the passkey offer, Guarda tu progreso).
class FingerprintIcon extends StatelessWidget {
  const FingerprintIcon({super.key});

  @override
  Widget build(BuildContext context) => _SvgIcon(paths: _fingerprint, fill: false, strokeWidth: 2);
}

final _moon = [
  parseSvgPath(
    'M20.5 14.6A8.6 8.6 0 0 1 9.4 3.5a.7.7 0 0 0-.9-.9A9.6 9.6 0 1 0 21.4 15.5a.7.7 0 0 0-.9-.9Z',
  ),
];

final _sunDisc = Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 4.5));

final _sunRays = [
  parseSvgPath(
    'M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.3 5.3l1.6 1.6M17.1 17.1l1.6 1.6'
    'M5.3 18.7l1.6-1.6M17.1 6.9l1.6-1.6',
  ),
];

/// The moon shown at night, the sun by day (the theme toggle's icon).
class ThemeIcon extends StatelessWidget {
  const ThemeIcon({super.key, required this.night});

  final bool night;

  @override
  Widget build(BuildContext context) => night
      ? _SvgIcon(paths: _moon, fill: true, strokeWidth: 0)
      : _SvgIcon(paths: _sunRays, fill: false, strokeWidth: 2, filledShapes: [_sunDisc]);
}

/// The parsed paths of every icon shape, made once.
final _parsed = <LkIconShape, Path>{};

Path _pathOf(LkIconShape shape) => _parsed.putIfAbsent(
  shape,
  () =>
      parseSvgPath(shape.d)..fillType = shape.evenOdd ? PathFillType.evenOdd : PathFillType.nonZero,
);

/// An interface icon (the web's `Icon`), [size] square, in [color] or the text colour around it.
/// Hidden from semantics: the button around it carries the name. Emoji stay for categories.
class LkIcon extends StatelessWidget {
  const LkIcon(
    this.name, {
    super.key,
    this.variant = LkIconVariant.filled,
    this.size = 24,
    this.color,
  });

  final LkIconName name;

  /// `outline` for an inactive tab.
  final LkIconVariant variant;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colour = color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _IconPainter(shapesOf(name, variant), colour),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.shapes, this.color);

  final List<LkIconShape> shapes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    for (final shape in shapes) {
      final paint = Paint()
        ..color = color
        ..isAntiAlias = true;
      if (shape.fill) {
        paint.style = PaintingStyle.fill;
      } else {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = shape.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
      }
      canvas.drawPath(_pathOf(shape), paint);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.color != color || old.shapes != shapes;
}
