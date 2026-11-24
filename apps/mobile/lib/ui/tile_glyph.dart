import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/text_styles.dart';

/// A category's emoji in its tinted tile (`LkText.tileGlyph`), centred in the tile on every phone.
///
/// On the iPhone, Apple Color Emoji leaves more room on the right of a glyph than on its left, and
/// the tile's line box is Nunito's, so the emoji sat about 1.5pt left and 1pt low of the tile's
/// centre at 17px (measured on the simulator). It is moved back by that much, in proportion to
/// [size]. On other phones it stays where the text puts it.
class TileGlyph extends StatelessWidget {
  const TileGlyph(this.glyph, {super.key, required this.color, this.size = 17});

  /// How far Apple Color Emoji's ink sits from the centre of its box, in em: x to the right, y down.
  static const _appleInkShift = Offset(-1.5 / 17, 1.1 / 17);

  final String glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      glyph,
      style: LkText.tileGlyph.copyWith(fontSize: size, color: color),
    );
    if (defaultTargetPlatform != TargetPlatform.iOS) return text;
    return Transform.translate(offset: -_appleInkShift * size, child: text);
  }
}
