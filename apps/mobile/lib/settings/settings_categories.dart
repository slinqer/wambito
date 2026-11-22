// The settings menu's categories, in the order the menu shows them. The phone has capture as well;
// the web does not, so [settingsCategories] can leave it out.

/// A category of the settings menu. [path] is its route.
enum SettingsCategory {
  agents,
  account,
  preferences,
  capture,
  data,
  more;

  /// The route of this category's page, such as `/settings/agents`.
  String get path => '/settings/$name';
}

/// The categories in menu order. With [webSectionsOnly] the phone shows only the sections the web
/// has, so capture is dropped.
List<SettingsCategory> settingsCategories({required bool webSectionsOnly}) => [
  for (final category in SettingsCategory.values)
    if (!(webSectionsOnly && category == SettingsCategory.capture)) category,
];
