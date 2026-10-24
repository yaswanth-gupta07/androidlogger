import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE material for the OAuth authorization-code flow.
class PkcePair {
  const PkcePair({required this.verifier, required this.challenge});

  final String verifier;
  final String challenge;

  static PkcePair generate({Random? random}) {
    final verifier = randomUrlToken(bytes: 32, random: random);
    return PkcePair(verifier: verifier, challenge: challengeFor(verifier));
  }

  /// S256 challenge, base64url encoded without padding.
  static String challengeFor(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}

String randomUrlToken({int bytes = 16, Random? random}) {
  final rng = random ?? Random.secure();
  final values = List<int>.generate(bytes, (_) => rng.nextInt(256));
  return base64UrlEncode(values).replaceAll('=', '');
}
