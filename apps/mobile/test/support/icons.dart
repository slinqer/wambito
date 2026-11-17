import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/ui/lk_icons.dart';

/// The [LkIcon]s named [name]: the month picker's arrows are `findIcon(LkIconName.chevronLeft)`
/// and `chevronRight`, where they once were the text ‹ and ›.
Finder findIcon(LkIconName name) =>
    find.byWidgetPredicate((widget) => widget is LkIcon && widget.name == name);
