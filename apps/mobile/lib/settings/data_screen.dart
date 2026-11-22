// Tus datos (`/settings/data`), the light version (spec 2026-11-22; twin of
// apps/web/app/features/settings/DataScreen.tsx): "Importar movimientos" (a chevron to the import; an
// encrypted account has "Próximamente" and no chevron) and "Descargar tus datos" (today's export
// choices in a sheet, `openExportSheet`). The longer sentences stay: the import's lead as its hint
// for a screen reader, the encrypted account's wording as the chip's.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../vault/preview.dart';
import 'export_settings.dart';
import 'settings_parts.dart';

class DataScreen extends ConsumerWidget {
  const DataScreen({super.key, required this.guest});

  /// A guest has no email to export under: the sheet's buttons are off.
  final bool guest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tint = context.lkColors.inkMuted;
    // The import and the export are the server's; an encrypted account's data is on the phone.
    final preview = ref.watch(isPreviewProvider);
    return SettingsGroup(
      key: const Key('settings.card.data'),
      rows: [
        if (preview)
          SettingsRow(
            key: const Key('settings.import.comingSoon'),
            icon: LkIcon(LkIconName.upload, size: 20, color: tint),
            title: l10n.settingsImportRow,
            line: l10n.settingsImportRowLine,
            semanticsHint: l10n.comingSoonWithEncryption,
            trailing: RowChip(l10n.settingsComingSoonChip),
          )
        else
          SettingsRow(
            key: const Key('settings.import'),
            icon: LkIcon(LkIconName.upload, size: 20, color: tint),
            title: l10n.settingsImportRow,
            line: l10n.settingsImportRowLine,
            semanticsHint: l10n.settingsImportLead,
            trailing: const RowChevron(),
            onTap: () => unawaited(context.push<void>('/import')),
          ),
        if (preview)
          SettingsRow(
            key: const Key('settings.export.comingSoon'),
            icon: LkIcon(LkIconName.download, size: 20, color: tint),
            title: l10n.settingsExportRow,
            line: l10n.settingsExportRowLine,
            semanticsHint: l10n.comingSoonWithEncryption,
            trailing: RowChip(l10n.settingsComingSoonChip),
          )
        else
          SettingsRow(
            key: const Key('settings.export'),
            icon: LkIcon(LkIconName.download, size: 20, color: tint),
            title: l10n.settingsExportRow,
            line: l10n.settingsExportRowLine,
            trailing: const RowChevron(),
            onTap: () => unawaited(openExportSheet(context, guest: guest)),
          ),
      ],
    );
  }
}
