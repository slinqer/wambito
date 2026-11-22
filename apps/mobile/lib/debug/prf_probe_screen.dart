// A debug-only probe of the passkey PRF on this phone (`/debug/prf`, registered only when
// `kDebugMode`). It shows SHA-256 of the PRF, never the PRF, and whether two reads match.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/session.dart';
import '../local/prf.dart';

String _hex(Uint8List prf) => sha256.convert(prf).toString();

class PrfProbeScreen extends ConsumerStatefulWidget {
  const PrfProbeScreen({super.key});

  @override
  ConsumerState<PrfProbeScreen> createState() => _PrfProbeScreenState();
}

class _PrfProbeScreenState extends ConsumerState<PrfProbeScreen> {
  String _out = '';
  bool _busy = false;

  Future<void> _run(Future<String> Function() body) async {
    setState(() {
      _busy = true;
      _out = '';
    });
    try {
      final text = await body();
      if (mounted) setState(() => _out = text);
    } on Object catch (error) {
      if (mounted) setState(() => _out = 'Error: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// `create` with the extension and `eval`, then registers the passkey so [_read] can use it.
  Future<String> _create() async {
    final passkeys = ref.read(passkeysProvider);
    final auth = ref.read(authApiProvider);
    final token = ref.read(sessionProvider).stored?.token;
    if (token == null) return 'Sign in first';
    final challenge = await auth.passkeyRegisterOptions(token);
    final options = (jsonDecode(challenge.optionsJson) as Map).cast<String, Object?>();
    options['extensions'] = prfExtension();
    final attestation = await passkeys.create(jsonEncode(options));
    await auth.passkeyRegister(token, challenge, attestation);
    final results =
        ((jsonDecode(attestation) as Map)['clientExtensionResults'] as Map?)
            ?.cast<String, Object?>() ??
        const {};
    final prf = readPrf(results);
    if (prf != null) return 'Created. SHA-256(prf): ${_hex(prf)}';
    return prfEnabledWithoutResults(results)
        ? 'Created. PRF enabled, no output yet: tap "Read PRF"'
        : 'Created. No PRF support: $results';
  }

  /// `get` twice with the extension: the hashes and whether they match.
  Future<String> _read() async {
    final passkeys = ref.read(passkeysProvider);
    final auth = ref.read(authApiProvider);
    final challenge = await auth.passkeySignInOptions();
    final first = await evaluatePrf(passkeys, challenge.optionsJson);
    if (first == null) return 'Cancelled';
    final again = await evaluatePrf(passkeys, (await auth.passkeySignInOptions()).optionsJson);
    if (again == null) return 'Cancelled';
    final a = _hex(first.prf);
    final b = _hex(again.prf);
    return 'SHA-256(prf): $a\nSecond read: $b\nMatch: ${a == b}\nCredential: ${first.credentialId}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Passkey PRF probe')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: _busy ? null : () => _run(_create),
            child: const Text('Create passkey with PRF'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : () => _run(_read), child: const Text('Read PRF')),
          const SizedBox(height: 24),
          SelectableText(_out),
        ],
      ),
    ),
  );
}
