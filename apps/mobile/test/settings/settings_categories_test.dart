// The settings categories: the phone's order, and the web's when the phone shows only the web's sections.
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/settings/settings_categories.dart';

void main() {
  test('the phone lists its six categories in order', () {
    expect(settingsCategories(webSectionsOnly: false), [
      SettingsCategory.agents,
      SettingsCategory.account,
      SettingsCategory.preferences,
      SettingsCategory.capture,
      SettingsCategory.data,
      SettingsCategory.more,
    ]);
  });

  test('with webSectionsOnly the capture category is dropped', () {
    expect(settingsCategories(webSectionsOnly: true), [
      SettingsCategory.agents,
      SettingsCategory.account,
      SettingsCategory.preferences,
      SettingsCategory.data,
      SettingsCategory.more,
    ]);
  });

  test('each category has its route path', () {
    expect(SettingsCategory.agents.path, '/settings/agents');
    expect(SettingsCategory.account.path, '/settings/account');
    expect(SettingsCategory.preferences.path, '/settings/preferences');
    expect(SettingsCategory.capture.path, '/settings/capture');
    expect(SettingsCategory.data.path, '/settings/data');
    expect(SettingsCategory.more.path, '/settings/more');
  });
}
