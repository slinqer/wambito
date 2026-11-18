import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asking the launcher to add Wambito's home-screen widget (`wambito/device`: `widgetInstalled`,
/// `widgetPinSupported`, `pinWidget`). Android answers; iOS and any failure answer false.
class WidgetPin {
  static const _channel = MethodChannel('wambito/device');

  /// A Wambito widget (small or medium) is already on a home screen.
  Future<bool> installed() => _ask('widgetInstalled');

  /// The launcher can be asked to add the widget.
  Future<bool> supported() => _ask('widgetPinSupported');

  /// Asks the launcher to add the widget. True means the launcher's dialog was shown, not that the
  /// widget was added (the person may decline): check [installed] afterwards.
  Future<bool> pin() => _ask('pinWidget');

  Future<bool> _ask(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final widgetPinProvider = Provider<WidgetPin>((ref) => WidgetPin());
