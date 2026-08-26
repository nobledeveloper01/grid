import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid/features/backup/data/archive_cipher.dart';

/// The archive leaves the device — to Files, to Drive, to a message the user
/// sends themselves — carrying two years of where somebody lives and what they
/// spend. These tests are about what happens to it out there.
void main() {
  const cipher = ArchiveCipher();
  const passphrase = 'correct horse battery staple';
  const plaintext = '{"version":1,"readings":[{"milli":39330100}]}';

  String sealed() =>
      cipher.seal(plaintext: plaintext, passphrase: passphrase);

  group('round trip', () {
    test('opens with the right passphrase', () {
      expect(
        cipher.open(envelope: sealed(), passphrase: passphrase),
        plaintext,
      );
    });

    test('survives a passphrase with spaces, case and non-ASCII', () {
      const awkward = 'Ọ̀gá 1234 — ṣé ó dára?';
      final envelope =
          cipher.seal(plaintext: plaintext, passphrase: awkward);
      expect(cipher.open(envelope: envelope, passphrase: awkward), plaintext);
    });

    test('handles an archive larger than one keystream block', () {
      // 32 bytes per HMAC block; a real archive is hundreds of kilobytes, and
      // an off-by-one in the counter loop would only show past the first one.
      final big = jsonEncode({
        'readings': [
          for (var i = 0; i < 5000; i++) {'id': 'r$i', 'milli': i * 1000},
        ],
      });
      final envelope = cipher.seal(plaintext: big, passphrase: passphrase);
      expect(cipher.open(envelope: envelope, passphrase: passphrase), big);
    });

    test('an empty archive is still a valid one', () {
      final envelope = cipher.seal(plaintext: '', passphrase: passphrase);
      expect(cipher.open(envelope: envelope, passphrase: passphrase), '');
    });
  });

  group('refusals', () {
    test('the wrong passphrase yields nothing, not noise', () {
      // Decrypting to garbage would surface downstream as "this archive is
      // damaged", which sends the user looking for a corrupted file instead
      // of the passphrase they mistyped.
      expect(
        cipher.open(envelope: sealed(), passphrase: 'not the passphrase'),
        isNull,
      );
    });

    test('a one-character difference is enough', () {
      expect(
        cipher.open(
          envelope: sealed(),
          passphrase: 'correct horse battery stapl3',
        ),
        isNull,
      );
    });

    test('a tampered ciphertext is refused', () {
      final envelope = jsonDecode(sealed()) as Map<String, dynamic>;
      final bytes = base64.decode(envelope['ciphertext'] as String);
      bytes[0] ^= 0xff;
      envelope['ciphertext'] = base64.encode(bytes);

      expect(
        cipher.open(
          envelope: jsonEncode(envelope),
          passphrase: passphrase,
        ),
        isNull,
      );
    });

    test('a tampered header is refused, including the iteration count', () {
      // The MAC covers the header for exactly this reason: an attacker who
      // could quietly lower the iteration count would make the next
      // decryption cheap to brute force.
      final envelope = jsonDecode(sealed()) as Map<String, dynamic>;
      (envelope['header'] as Map<String, dynamic>)['iterations'] = 1001;

      expect(
        cipher.open(
          envelope: jsonEncode(envelope),
          passphrase: passphrase,
        ),
        isNull,
      );
    });

    test('an absurdly low iteration count is rejected outright', () {
      final envelope = jsonDecode(sealed()) as Map<String, dynamic>;
      (envelope['header'] as Map<String, dynamic>)['iterations'] = 1;

      expect(
        cipher.open(
          envelope: jsonEncode(envelope),
          passphrase: passphrase,
        ),
        isNull,
      );
    });

    test('a file that is not an envelope is rejected by shape', () {
      expect(
        cipher.open(envelope: 'not json at all', passphrase: passphrase),
        isNull,
      );
      expect(
        cipher.open(envelope: '{"hello":"world"}', passphrase: passphrase),
        isNull,
      );
    });

    test('a newer envelope version is refused rather than misread', () {
      final envelope = jsonDecode(sealed()) as Map<String, dynamic>;
      (envelope['header'] as Map<String, dynamic>)['v'] =
          ArchiveCipher.envelopeVersion + 1;

      expect(
        cipher.open(
          envelope: jsonEncode(envelope),
          passphrase: passphrase,
        ),
        isNull,
      );
    });
  });

  group('the envelope itself', () {
    test('carries no plaintext', () {
      // The most basic thing to get wrong, and the easiest to miss: a header
      // field that helpfully records what was encrypted.
      final envelope = sealed();
      expect(envelope.contains('39330100'), isFalse);
      expect(envelope.contains('readings'), isFalse);
    });

    test('never carries the passphrase or a hash of it', () {
      final envelope = sealed();
      expect(envelope.contains(passphrase), isFalse);
      expect(envelope.toLowerCase().contains('horse'), isFalse);
    });

    test('is different every time, even for identical input', () {
      // A fresh salt and nonce per archive. Identical envelopes would tell an
      // observer that two backups hold the same record.
      expect(sealed(), isNot(sealed()));
    });

    test('describes how it was made, so a later Grid can open it', () {
      final header =
          (jsonDecode(sealed()) as Map<String, dynamic>)['header'] as Map;
      expect(header['magic'], ArchiveCipher.magic);
      expect(header['kdf'], 'pbkdf2-hmac-sha256');
      expect(header['iterations'], greaterThanOrEqualTo(200000));
      expect(header['salt'], isA<String>());
      expect(header['nonce'], isA<String>());
    });
  });
}
