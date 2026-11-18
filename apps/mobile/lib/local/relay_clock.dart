/// The clock the relays (`pairing.dart`, `signin_approval.dart`) poll by and count their deadline
/// on: this phone's own, never the server's. Tests pass a fake one.
abstract interface class PairingClock {
  DateTime now();
  Future<void> sleep(Duration d);
}

/// [PairingClock] on the phone's wall clock and real timers.
class RealPairingClock implements PairingClock {
  const RealPairingClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Future<void> sleep(Duration d) => Future<void>.delayed(d);
}
