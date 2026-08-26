import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Encrypting an archive with a passphrase the user chose.
///
/// The threat this addresses is specific and worth stating, because it decides
/// how much machinery is warranted: the archive leaves the device. It goes to
/// Files, to Drive, to a WhatsApp message the user sends themselves. Anywhere
/// it lands is somewhere Grid does not control, and it contains two years of
/// where somebody lives and what they spend.
///
/// **What this is not.** It is not protection against an adversary with the
/// device, who has the database itself. It is not a key-management system.
/// There is no recovery: a forgotten passphrase means a lost archive, and the
/// UI says so before the user commits to one.
///
/// The construction is deliberately conservative and built only from what the
/// project already depends on — `package:crypto`, which ships SHA-256 and
/// HMAC. Adding a cipher library for one feature would widen the supply-chain
/// surface of an application that currently has none of that risk.
///
///   * Key derivation is PBKDF2-HMAC-SHA256, 210,000 iterations, 16-byte salt.
///     The iteration count follows current OWASP guidance for that PRF; it is
///     stored in the header so raising it later does not orphan old archives.
///   * The stream cipher is HMAC-SHA256 in counter mode — a standard KDF-in-
///     CTR construction, keyed separately from the MAC.
///   * Authentication is encrypt-then-MAC: HMAC-SHA256 over header, nonce and
///     ciphertext, with an independent key. A wrong passphrase fails the MAC
///     and the archive is refused rather than decrypting to noise that the
///     JSON parser would then report as "damaged".
class ArchiveCipher {
  const ArchiveCipher();

  /// Bumped only when the construction changes. Separate from the archive's
  /// own format version, because the two move for different reasons.
  static const int envelopeVersion = 1;

  static const int _iterations = 210000;
  static const int _saltBytes = 16;
  static const int _nonceBytes = 16;

  /// Magic so a wrong file is rejected by shape, not by a MAC failure that
  /// would otherwise be reported as a wrong passphrase.
  static const String magic = 'GRIDBAK1';

  /// Encrypts [plaintext] under [passphrase], returning a self-describing
  /// envelope safe to write anywhere.
  String seal({required String plaintext, required String passphrase}) {
    final rng = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(_saltBytes, (_) => rng.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(_nonceBytes, (_) => rng.nextInt(256)),
    );

    final keys = _derive(passphrase, salt, _iterations);
    final body = Uint8List.fromList(utf8.encode(plaintext));
    final cipher = _xorKeystream(body, keys.encryption, nonce);

    final header = <String, dynamic>{
      'magic': magic,
      'v': envelopeVersion,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _iterations,
      'salt': base64.encode(salt),
      'nonce': base64.encode(nonce),
    };

    // Encrypt-then-MAC, over the header as well: an attacker who could edit
    // the iteration count downward without detection could make the next
    // decryption cheap to brute force.
    final headerJson = jsonEncode(header);
    final mac = Hmac(sha256, keys.authentication).convert([
      ...utf8.encode(headerJson),
      ...nonce,
      ...cipher,
    ]);

    return jsonEncode({
      'header': header,
      'ciphertext': base64.encode(cipher),
      'mac': base64.encode(mac.bytes),
    });
  }

  /// Decrypts an envelope. Returns null when the passphrase is wrong or the
  /// archive has been altered — the two are not distinguished, deliberately,
  /// because telling them apart tells an attacker which one they got right.
  String? open({required String envelope, required String passphrase}) {
    final Map<String, dynamic> outer;
    try {
      final decoded = jsonDecode(envelope);
      if (decoded is! Map<String, dynamic>) return null;
      outer = decoded;
    } on FormatException {
      return null;
    }

    final header = outer['header'];
    if (header is! Map<String, dynamic>) return null;
    if (header['magic'] != magic) return null;

    final version = header['v'];
    if (version is! int || version > envelopeVersion) return null;

    final iterations = header['iterations'];
    if (iterations is! int || iterations < 1000) return null;

    final Uint8List salt;
    final Uint8List nonce;
    final Uint8List cipher;
    final Uint8List mac;
    try {
      salt = base64.decode(header['salt'] as String);
      nonce = base64.decode(header['nonce'] as String);
      cipher = base64.decode(outer['ciphertext'] as String);
      mac = base64.decode(outer['mac'] as String);
    } on Object {
      return null;
    }

    final keys = _derive(passphrase, salt, iterations);
    final expected = Hmac(sha256, keys.authentication).convert([
      ...utf8.encode(jsonEncode(header)),
      ...nonce,
      ...cipher,
    ]);

    if (!_constantTimeEquals(expected.bytes, mac)) return null;

    try {
      return utf8.decode(_xorKeystream(cipher, keys.encryption, nonce));
    } on FormatException {
      return null;
    }
  }

  // --- construction ---------------------------------------------------------

  _Keys _derive(String passphrase, Uint8List salt, int iterations) {
    // Two independent keys from one passphrase: never use the same key to
    // encrypt and to authenticate.
    final master = _pbkdf2(
      utf8.encode(passphrase),
      salt,
      iterations,
      64,
    );
    return _Keys(
      encryption: master.sublist(0, 32),
      authentication: master.sublist(32, 64),
    );
  }

  Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int length,
  ) {
    final prf = Hmac(sha256, password);
    final out = BytesBuilder();
    var block = 1;

    while (out.length < length) {
      // U1 = PRF(password, salt || INT(block))
      var u = Uint8List.fromList(
        prf.convert([...salt, ..._intBytes(block)]).bytes,
      );
      final acc = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(prf.convert(u).bytes);
        for (var j = 0; j < acc.length; j++) {
          acc[j] ^= u[j];
        }
      }
      out.add(acc);
      block++;
    }

    return Uint8List.fromList(out.toBytes().sublist(0, length));
  }

  List<int> _intBytes(int value) => [
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ];

  /// HMAC-SHA256 in counter mode. Each block is HMAC(key, nonce || counter),
  /// XORed into the plaintext.
  Uint8List _xorKeystream(Uint8List input, Uint8List key, Uint8List nonce) {
    final prf = Hmac(sha256, key);
    final out = Uint8List(input.length);

    var offset = 0;
    var counter = 0;
    while (offset < input.length) {
      final block = prf.convert([...nonce, ..._intBytes(counter)]).bytes;
      for (var i = 0; i < block.length && offset < input.length; i++) {
        out[offset] = input[offset] ^ block[i];
        offset++;
      }
      counter++;
    }
    return out;
  }

  /// Compares in constant time. A short-circuiting comparison on a MAC leaks
  /// how much of a forgery was right, one byte at a time.
  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class _Keys {
  const _Keys({required this.encryption, required this.authentication});
  final Uint8List encryption;
  final Uint8List authentication;
}
