import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The camera's QR scan, in the phone's own code (`wambito/scanner`): CameraX with ZXing core on
/// Android (android/.../scanner/), AVFoundation on iOS (ios/Runner/Scanner/). No Google Play
/// Services, no ML Kit. The camera opens only inside [scan], full screen, and the permission is
/// asked there, never at start.
abstract interface class QrScanner {
  /// Whether this phone has a camera to scan with. False means the screen shows the typed code only.
  Future<bool> isAvailable();

  /// Opens the camera and answers the first `wambito://pair?` QR it reads. Null when the person
  /// closed it or did not give the camera permission (nothing to say then). Throws a
  /// [PlatformException] when the camera could not start.
  Future<String?> scan();
}

/// [QrScanner] over `wambito/scanner`; a phone with no such channel has no scanner.
class MethodQrScanner implements QrScanner {
  const MethodQrScanner();

  static const _channel = MethodChannel('wambito/scanner');

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String?> scan() async {
    try {
      return await _channel.invokeMethod<String>('scan');
    } on MissingPluginException {
      return null;
    }
  }
}

/// The phone's scanner (replaced in tests).
final qrScannerProvider = Provider<QrScanner>((ref) => const MethodQrScanner());
