#!/usr/bin/env bash
# Regenerates the widget picker's previews (android/app/src/main/res/drawable-nodpi/
# widget_preview_{small,medium}.png) from the real widget: WidgetPreviewsTest draws them with
# Glance under Robolectric's native graphics, then this copies them in. Run from apps/mobile after
# any change to the widget's look, with JAVA_HOME set to a JDK 17.
set -euo pipefail
cd "$(dirname "$0")/../android"
out=app/build/widget-previews
rm -rf "$out"
./gradlew :app:testDebugUnitTest --tests 'com.wambito.app.widget.WidgetPreviewsTest' \
  --rerun --console=plain -x compileFlutterBuildDebug
for size in small medium; do
  cp "$out/widget_preview_$size.png" "app/src/main/res/drawable-nodpi/widget_preview_$size.png"
done
echo "Copied the previews into app/src/main/res/drawable-nodpi."
