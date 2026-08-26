import 'dart:convert';
import 'dart:io';

import '../../../domain/services/allocation_engine.dart';
import '../../../domain/value_objects/units.dart';

/// One issued statement link, as the server returned it.
class IssuedStatement {
  const IssuedStatement({
    required this.id,
    required this.name,
    required this.shareUrl,
    required this.amount,
  });

  final String id;
  final String name;

  /// Absolute, ready to send. The server returns a path; the base URL the
  /// landlord configured is joined here rather than in the UI, so a link that
  /// reaches a tenant is never half a URL.
  final String shareUrl;

  final Naira amount;
}

/// Why issuing failed, in words a landlord can act on.
class StatementError implements Exception {
  const StatementError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Talks to the Grid server.
///
/// This is the only outbound network call in the entire application, and it
/// happens because a landlord pressed a button. Nothing else in Grid reaches
/// the network at all, which is why this lives in one small file with an
/// explicit timeout rather than behind a general-purpose HTTP layer that
/// something else could quietly start using.
class StatementClient {
  const StatementClient({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  Future<List<IssuedStatement>> issue({
    required String baseUrl,
    required String apiKey,
    required String meterNumber,
    required String disco,
    required Allocation allocation,
    required List<Occupant> occupants,
  }) async {
    final base = _normalise(baseUrl);
    final uri = Uri.parse('$base/v1/statements');

    final body = jsonEncode({
      'meter_number': meterNumber,
      'disco': disco,
      'period_start': allocation.periodStart.toUtc().toIso8601String(),
      'period_end': allocation.periodEnd.toUtc().toIso8601String(),
      'rule': allocation.rule.name,
      'total_kobo': allocation.total.kobo,
      'total_energy_milli': allocation.totalEnergy.milli,
      'occupants': [
        for (final o in occupants)
          {
            'id': o.id,
            'name': o.name,
            'rooms': o.rooms,
            'weight': o.weight,
          },
      ],
    });

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.contentType = ContentType.json;
      request.write(body);

      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.unauthorized) {
        throw const StatementError(
          'The server did not accept that key. Check it in Settings.',
        );
      }
      if (response.statusCode >= 400) {
        // The server's own message where it gave one — it knows more about
        // why than a generic failure string does.
        final reason = _reasonFrom(text) ?? 'the server refused it';
        throw StatementError('Could not issue statements: $reason.');
      }

      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final list = (decoded['statements'] as List<dynamic>? ?? const []);
      return [
        for (final raw in list)
          () {
            final m = raw as Map<String, dynamic>;
            return IssuedStatement(
              id: m['id'] as String,
              name: m['name'] as String,
              shareUrl: '$base${m['share_url']}',
              amount: Naira.fromKobo((m['amount_kobo'] as num).toInt()),
            );
          }(),
      ];
    } on SocketException {
      throw const StatementError(
        'Could not reach the server. Grid works offline for everything else — '
        'this is the one thing that needs a connection.',
      );
    } on HttpException {
      throw const StatementError('The server did not answer properly.');
    } on FormatException {
      throw const StatementError(
        'That address does not look like a server Grid can talk to.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Trims a trailing slash so `$base$path` never doubles it.
  static String _normalise(String raw) {
    final trimmed = raw.trim();
    // Case-insensitive: a keyboard that capitalises the first letter turns
    // `http://` into `HTTP://`, which is a perfectly valid scheme and was not
    // recognised as one — the result was `https://HTTP://host`.
    final hasScheme = trimmed.toLowerCase().startsWith('http');
    final withScheme = hasScheme ? trimmed : 'https://$trimmed';
    return withScheme.endsWith('/')
        ? withScheme.substring(0, withScheme.length - 1)
        : withScheme;
  }

  static String? _reasonFrom(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      // A non-JSON error body is not worth surfacing verbatim.
    }
    return null;
  }
}
