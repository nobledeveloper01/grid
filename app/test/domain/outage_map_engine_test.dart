import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/entities/supply_event.dart';
import 'package:grid/domain/services/outage_map_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';

import '_fixtures.dart';

void main() {
  const engine = OutageMapEngine();
  final windowStart = now.subtract(const Duration(days: 7));

  /// Fully-observed days at [hoursOn] hours each.
  List<SupplyEvent> days(int count, {int hoursOn = 8}) {
    final out = <SupplyEvent>[];
    for (var d = count; d >= 1; d--) {
      final start =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
      out.add(supply(
        id: 'on-$d',
        state: SupplyState.available,
        from: start,
        to: start.add(Duration(hours: hoursOn)),
      ));
      out.add(supply(
        id: 'off-$d',
        state: SupplyState.unavailable,
        from: start.add(Duration(hours: hoursOn)),
        to: start.add(const Duration(hours: 24)),
      ));
    }
    return out;
  }

  ContributionResult prepare({
    String? lga = 'Surulere',
    List<SupplyEvent>? events,
  }) =>
      engine.prepare(
        lga: lga,
        disco: DisCo.ikeja,
        band: TariffBand.a,
        events: events ?? days(6),
        windowStart: windowStart,
        windowEnd: now,
        now: now,
      );

  group('the privacy gate', () {
    test('the payload carries nothing finer than an LGA', () {
      // The gate, as a test. Coordinates, an address or a meter number would
      // let anyone holding the aggregate walk it back to a person.
      final reports = (prepare() as ContributionReady).reports;
      final json = jsonEncode([for (final r in reports) r.toJson()]);

      expect(json, contains('Surulere'));
      for (final forbidden in [
        'address',
        'meterNumber',
        'meter_number',
        'lat',
        'lon',
        'coord',
        '04123456789',
      ]) {
        expect(json.toLowerCase(), isNot(contains(forbidden.toLowerCase())),
            reason: '$forbidden must never leave the device');
      }
    });

    test('a date carries no time of day', () {
      // A timestamp to the minute, with an LGA and a band, is close to a
      // fingerprint.
      final reports = (prepare() as ContributionReady).reports;
      for (final r in reports) {
        final encoded = r.toJson()['date'] as String;
        expect(encoded, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        expect(encoded, isNot(contains(':')));
      }
    });

    test('the payload has exactly the fields the consent screen names', () {
      final reports = (prepare() as ContributionReady).reports;
      expect(
        reports.first.toJson().keys.toSet(),
        {'lga', 'disco', 'date', 'hours', 'coverage', 'band'},
      );
    });

    test('the consent copy is generated from the payload, not written', () {
      // A consent screen describing an older version of the payload is worse
      // than no consent screen.
      final reports = (prepare() as ContributionReady).reports;
      final described = engine.describe(reports).join(' ');
      expect(described, contains('Surulere'));
      expect(described, contains('Ikeja'));
      expect(described, contains('Band A'));
      expect(described, contains('${reports.length} days'));
    });

    test('what is withheld is stated too', () {
      final withheld = engine.describeWithheld().join(' ').toLowerCase();
      expect(withheld, contains('address'));
      expect(withheld, contains('meter number'));
      expect(withheld, contains('times of day'));
    });
  });

  group('refusals', () {
    test('no LGA means nothing to aggregate by', () {
      final out = prepare(lga: null) as ContributionBlocked;
      expect(out.reason, ContributionGap.noArea);
      expect(out.detail, contains('local government area'));
    });

    test('blank whitespace is not an area', () {
      expect((prepare(lga: '   ') as ContributionBlocked).reason,
          ContributionGap.noArea);
    });

    test('poorly observed days are not shared', () {
      // Pooling a day nobody observed does not make it evidence.
      final out = prepare(events: const []) as ContributionBlocked;
      expect(out.reason, ContributionGap.noUsableDays);
    });

    test('only usable days make it into the payload', () {
      final mixed = [
        ...days(3),
        // A day with two observed hours out of twenty-four.
        supply(
          id: 'thin',
          state: SupplyState.available,
          from: DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 5)),
          to: DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 5))
              .add(const Duration(hours: 2)),
        ),
      ];
      final reports = (prepare(events: mixed) as ContributionReady).reports;
      expect(reports, hasLength(3));
    });
  });

  group('aggregation', () {
    OutageReport report(String lga, int daysAgo, double hours) => OutageReport(
          lga: lga,
          disco: DisCo.ikeja,
          date: DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: daysAgo)),
          hoursWithSupply: hours,
          coverage: 1,
          band: TariffBand.a,
        );

    test('pools a street into one figure per area per day', () {
      final pooled = engine.aggregate([
        report('Surulere', 1, 8),
        report('Surulere', 1, 6),
        report('Surulere', 1, 7),
        report('Yaba', 1, 14),
      ]);

      expect(pooled, hasLength(2));
      final surulere = pooled.firstWhere((a) => a.lga == 'Surulere');
      expect(surulere.households, 3);
      expect(surulere.medianHours, 7);
      expect(surulere.worstHours, 6);
      expect(surulere.bestHours, 8);
    });

    test('uses the median, so one odd log does not move the picture', () {
      // A household on a generator-fed meter, or one with a broken log,
      // would drag an average.
      final pooled = engine.aggregate([
        report('Surulere', 1, 6),
        report('Surulere', 1, 6),
        report('Surulere', 1, 7),
        report('Surulere', 1, 6),
        report('Surulere', 1, 24),
      ]);
      expect(pooled.single.medianHours, 6);
    });

    test('an even number of households still has a median', () {
      final pooled = engine.aggregate([
        report('Surulere', 1, 6),
        report('Surulere', 1, 8),
      ]);
      expect(pooled.single.medianHours, 7);
    });

    test('two households are not a feeder, and it says so', () {
      final thin = engine.aggregate([
        report('Surulere', 1, 6),
        report('Surulere', 1, 8),
      ]).single;
      expect(thin.isCredible, isFalse);

      final many = engine.aggregate([
        for (var i = 0; i < 6; i++) report('Surulere', 1, 6),
      ]).single;
      expect(many.isCredible, isTrue);
    });

    test('a wide spread means the problem was probably in one house', () {
      // Which matters: it stops somebody taking a feeder complaint to a DisCo
      // about their own wiring.
      final shared = engine.aggregate([
        report('Surulere', 1, 6),
        report('Surulere', 1, 6.5),
        report('Surulere', 1, 6.2),
      ]).single;
      expect(shared.spread, lessThan(1));

      final notShared = engine.aggregate([
        report('Surulere', 1, 2),
        report('Surulere', 1, 18),
      ]).single;
      expect(notShared.spread, greaterThan(10));
    });

    test('newest first, so the view opens on what just happened', () {
      final pooled = engine.aggregate([
        report('Surulere', 5, 6),
        report('Surulere', 1, 8),
        report('Surulere', 3, 7),
      ]);
      expect(pooled.first.date.isAfter(pooled.last.date), isTrue);
    });

    test('nothing pooled yields nothing, not a division by zero', () {
      expect(engine.aggregate(const []), isEmpty);
    });
  });
}
