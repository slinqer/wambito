# Native crypto and PRF checks for the phone's stage 3b

Report for Task 1 of the stage 3b plan. Merge gate: the shared vectors on a real iPhone and the
PRF probe on both phones. Status: simulator done, devices pending the founder.

## Done

- The shared crypto vectors (`packages/crypto/test-vectors.json`) run through
  `apps/mobile/integration_test/crypto_vectors_test.dart` with the native implementation
  (`FlutterCryptography`) on the iOS simulator (iPhone 18 Pro): 12/12 passed (the native-engine
  assertion plus the 11 vectors).

## For the founder

Not run yet, and needed before merging:

1. The vectors on the real iPhone:
   `apps/mobile/scripts/run-native-vectors.sh <device-id>` (expect 12/12). Record the device, the iOS
   version and PASS or FAIL.
2. The PRF probe on both phones: Settings, About, "PRF probe" (debug build only). Record, for the
   iPhone and the Android phone: the device, the OS version, whether the PRF is stable across two
   reads, and whether it equals the web's fingerprint. A PRF failure on one platform does not block
   3b (spec 3) but is a merge-gate item.
