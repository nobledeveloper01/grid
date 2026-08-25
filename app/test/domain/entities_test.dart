import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/entities/meter.dart';
import 'package:grid/domain/entities/reading.dart';
import 'package:grid/domain/services/compliance_engine.dart';
import 'package:grid/domain/services/consumption_engine.dart';
import 'package:grid/domain/services/validation_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

void main() {
  group('MeterType', () {
    test('maps prepaid to a decrementing register', () {
      expect(MeterType.prepaidKeypad.direction, MeterDirection.decrementing);
      expect(MeterType.prepaidKeypad.isPrepaid, isTrue);
      expect(MeterType.prepaidKeypad.isReadable, isTrue);
    });

    test('maps both postpaid types to an incrementing register', () {
      expect(MeterType.postpaidDigital.direction, MeterDirection.incrementing);
      expect(MeterType.postpaidAnalogue.direction, MeterDirection.incrementing);
    });

    test('an unmetered connection has nothing to read', () {
      expect(MeterType.unmeteredEstimated.direction, MeterDirection.none);
      expect(MeterType.unmeteredEstimated.isReadable, isFalse);
    });

    test('every type carries a label and a description', () {
      for (final t in MeterType.values) {
        expect(t.label, isNotEmpty);
        expect(t.description, isNotEmpty);
      }
    });
  });

  group('TariffBand', () {
    test('carries the committed daily supply hours', () {
      expect(TariffBand.a.committedHours, 20);
      expect(TariffBand.e.committedHours, 4);
    });

    test('commitments decrease monotonically down the bands', () {
      final hours = TariffBand.values.map((b) => b.committedHours).toList();
      for (var i = 1; i < hours.length; i++) {
        expect(hours[i], lessThan(hours[i - 1]));
      }
    });

    test('states its commitment in words', () {
      expect(TariffBand.a.commitment, contains('20 hours'));
    });
  });

  group('DisCo', () {
    test('covers the eleven distribution companies plus other', () {
      expect(DisCo.values.length, 12);
      expect(DisCo.values.map((d) => d.code).toSet().length, 12);
    });
  });

  group('SupplyState and PlatformCapability', () {
    test('every state has a label', () {
      for (final s in SupplyState.values) {
        expect(s.label, isNotEmpty);
      }
    });

    test('expected coverage falls as platform capability weakens', () {
      expect(
        PlatformCapability.continuous.expectedCoverage,
        greaterThan(PlatformCapability.periodic.expectedCoverage),
      );
      expect(
        PlatformCapability.periodic.expectedCoverage,
        greaterThan(PlatformCapability.foregroundOnly.expectedCoverage),
      );
    });
  });

  group('ReadingFlag bitmask', () {
    test('sets, reads and clears flags', () {
      var flags = 0;
      expect(flags.has(ReadingFlag.anomalousHigh), isFalse);
      flags = flags.withFlag(ReadingFlag.anomalousHigh);
      expect(flags.has(ReadingFlag.anomalousHigh), isTrue);
      flags = flags.withoutFlag(ReadingFlag.anomalousHigh);
      expect(flags.has(ReadingFlag.anomalousHigh), isFalse);
    });

    test('holds several flags at once', () {
      final flags = 0
          .withFlag(ReadingFlag.anomalousHigh)
          .withFlag(ReadingFlag.userEdited);
      expect(flags.flags, {ReadingFlag.anomalousHigh, ReadingFlag.userEdited});
    });

    test('only some flags disqualify a reading from the baseline', () {
      expect(0.withFlag(ReadingFlag.anomalousHigh).excludedFromBaseline, isTrue);
      expect(0.withFlag(ReadingFlag.userEdited).excludedFromBaseline, isFalse);
      expect(
        0.withFlag(ReadingFlag.lowOcrConfidence).excludedFromBaseline,
        isFalse,
      );
    });

    test('flags are distinct powers of two', () {
      final bits = ReadingFlag.values.map((f) => f.bit).toList();
      expect(bits.toSet().length, bits.length);
      for (final b in bits) {
        expect(b & (b - 1), 0, reason: '$b is not a power of two');
      }
    });
  });

  group('Reading', () {
    test('is clean only when neither superseded nor baseline-excluded', () {
      expect(reading(id: 'a', value: 100, at: now).isClean, isTrue);
      expect(
        reading(id: 'b', value: 100, at: now, supersededById: 'c').isClean,
        isFalse,
      );
      expect(
        reading(
          id: 'd',
          value: 100,
          at: now,
          flags: ReadingFlag.anomalousHigh.bit,
        ).isClean,
        isFalse,
      );
    });

    test('copyWith preserves identity and evidence', () {
      final original = Reading(
        id: 'r1',
        meterId: 'm1',
        value: Kwh.fromDouble(100),
        readAt: now,
        recordedAt: now,
        source: ReadingSource.ocr,
        ocrConfidence: 0.91,
        photoPath: '/photos/r1.jpg',
        photoSha256: 'abc',
      );
      final edited = original.copyWith(
        value: Kwh.fromDouble(110),
        flags: ReadingFlag.userEdited.bit,
      );
      expect(edited.id, original.id);
      expect(edited.photoPath, '/photos/r1.jpg');
      expect(edited.photoSha256, 'abc');
      expect(edited.ocrConfidence, 0.91);
      expect(edited.value.value, 110);
      expect(edited.hasEvidence, isTrue);
    });

    test('equality is by id', () {
      final a = reading(id: 'same', value: 1, at: now);
      final b = reading(id: 'same', value: 999, at: now);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('Purchase', () {
    test('computes the effective rate actually paid', () {
      final p = purchase(id: 'p', naira: 22500, units: 100, at: now);
      expect(p.effectiveRate!.value, closeTo(225, 0.01));
    });

    test('reports no effective rate when units were derived, not observed', () {
      final p = Purchase(
        id: 'p',
        meterId: 'm1',
        amount: Naira.fromNaira(22500),
        units: Kwh.fromDouble(100),
        unitsDerived: true,
        purchasedAt: now,
      );
      expect(p.effectiveRate, isNull);
    });

    test('reports no effective rate when units are unknown', () {
      expect(purchase(id: 'p', naira: 22500, at: now).effectiveRate, isNull);
    });
  });

  group('SupplyEvent', () {
    test('clips its overlap to a window', () {
      final e = supply(
        id: 'e',
        state: SupplyState.available,
        from: now.subtract(const Duration(hours: 4)),
        to: now.add(const Duration(hours: 4)),
      );
      expect(
        e.overlapMinutes(now.subtract(const Duration(hours: 1)), now, now),
        60,
      );
    });

    test('reports zero overlap outside the window', () {
      final e = supply(
        id: 'e',
        state: SupplyState.available,
        from: now.subtract(const Duration(days: 5)),
        to: now.subtract(const Duration(days: 4)),
      );
      expect(e.overlapMinutes(now.subtract(const Duration(hours: 1)), now, now), 0);
    });

    test('treats an ongoing event as running up to now', () {
      final e = supply(
        id: 'e',
        state: SupplyState.available,
        from: now.subtract(const Duration(hours: 3)),
      );
      expect(e.isOngoing, isTrue);
      expect(e.durationAt(now).inHours, 3);
    });

    test('knows whether it was inferred', () {
      expect(
        supply(
          id: 'e',
          state: SupplyState.available,
          from: now,
          source: SupplySource.inferredCharging,
        ).isInferred,
        isTrue,
      );
    });
  });

  group('Appliance', () {
    test('copyWith preserves identity and scope', () {
      final a = appliance(id: 'a', name: 'Fan', watts: 75, hours: 10);
      final b = a.copyWith(quantity: 3);
      expect(b.id, 'a');
      expect(b.meterId, 'm1');
      expect(b.quantity, 3);
      expect(b.modelledDailyKwh.value, closeTo(2.25, 0.01));
    });

    test('equality is by id', () {
      expect(
        appliance(id: 'x', name: 'A', watts: 1, hours: 1),
        equals(appliance(id: 'x', name: 'B', watts: 999, hours: 9)),
      );
    });
  });

  group('unmetered connections', () {
    test('consume nothing derivable — there is no register to read', () {
      const engine = ConsumptionEngine();
      final s = engine.series(
        meter: meter(type: MeterType.unmeteredEstimated),
        readings: dailyRun(start: 100, perDay: 10, days: 4, endingAt: now),
      );
      expect(s.total, Kwh.zero);
      expect(s.dailyMean, 0);
    });

    test('validation raises no direction warning for them', () {
      const engine = ValidationEngine();
      final outcome = engine.validate(
        meter: meter(type: MeterType.unmeteredEstimated),
        candidate: Kwh.fromDouble(50),
        readAt: now,
        history: [
          reading(id: 'a', value: 60, at: now.subtract(const Duration(days: 1))),
        ],
      );
      expect(
        outcome.warnings.any(
          (w) => w.flagIfConfirmed == ReadingFlag.rolloverOrReplacement,
        ),
        isFalse,
      );
    });
  });

  group('ConsumptionSeries.dailyMean', () {
    test('is zero with no days', () {
      const empty = ConsumptionSeries(
        intervals: [],
        daily: [],
        total: Kwh.zero,
        excludedReadingCount: 0,
        coverage: 0,
      );
      expect(empty.dailyMean, 0);
    });

    test('averages across the covered days', () {
      const engine = ConsumptionEngine();
      final s = engine.series(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 12, days: 5, endingAt: now),
      );
      expect(s.dailyMean, closeTo(12, 1.0));
    });
  });

  group('explicit unknown supply', () {
    test('contributes to neither available nor unavailable time', () {
      const engine = ComplianceEngine();
      final day = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1));
      final s = engine.summarise(
        events: [
          supply(
            id: 'a',
            state: SupplyState.available,
            from: day,
            to: day.add(const Duration(hours: 8)),
          ),
          supply(
            id: 'u',
            state: SupplyState.unknown,
            from: day.add(const Duration(hours: 8)),
            to: day.add(const Duration(hours: 24)),
          ),
        ],
        windowStart: day,
        windowEnd: day.add(const Duration(hours: 23)),
        now: now,
      );
      final d = s.days.first;
      expect(d.availableMinutes, 8 * 60);
      expect(d.unavailableMinutes, 0);
      expect(d.unknownMinutes, 16 * 60);
    });
  });

  group('Meter', () {
    test('exposes direction and prepaid status from its type', () {
      expect(meter(type: MeterType.prepaidKeypad).isPrepaid, isTrue);
      expect(
        meter(type: MeterType.prepaidKeypad).direction,
        MeterDirection.decrementing,
      );
      expect(meter().isPrepaid, isFalse);
      expect(meter().direction, MeterDirection.incrementing);
    });

    test('is not a sub-meter unless it has a parent', () {
      expect(meter().isSubMeter, isFalse);
    });

    test('copyWith preserves identity, creation time and parentage', () {
      final original = Meter(
        id: 'm9',
        label: 'Flat 3',
        type: MeterType.postpaidAnalogue,
        disco: DisCo.eko,
        createdAt: now.subtract(const Duration(days: 400)),
        parentMeterId: 'main',
        unitId: 'u3',
        meterNumber: '0123456789',
      );
      final edited = original.copyWith(
        label: 'Flat 3 (rear)',
        tariffBand: TariffBand.b,
        rateOverride: Rate.fromNaira(180),
        supplyDetectionEnabled: false,
        isArchived: true,
      );

      expect(edited.id, 'm9');
      expect(edited.createdAt, original.createdAt);
      expect(edited.parentMeterId, 'main');
      expect(edited.unitId, 'u3');
      expect(edited.isSubMeter, isTrue);
      expect(edited.meterNumber, '0123456789');
      expect(edited.label, 'Flat 3 (rear)');
      expect(edited.tariffBand, TariffBand.b);
      expect(edited.rateOverride!.value, closeTo(180, 0.01));
      expect(edited.supplyDetectionEnabled, isFalse);
      expect(edited.isArchived, isTrue);
    });

    test('equality is by id', () {
      expect(meter(), equals(meter(type: MeterType.prepaidKeypad)));
      expect(meter().hashCode, meter().hashCode);
    });
  });

  group('Kwh arithmetic completeness', () {
    test('scales and divides', () {
      expect((Kwh.fromDouble(10) * 2.5).value, closeTo(25, 1e-9));
      expect((Kwh.fromDouble(10) / 4).value, closeTo(2.5, 1e-9));
    });

    test('reports zero and absolute value', () {
      expect(Kwh.zero.isZero, isTrue);
      expect(Kwh.fromDouble(-5).abs.value, 5);
    });

    test('supports the full comparison set', () {
      expect(Kwh.fromDouble(1) < Kwh.fromDouble(2), isTrue);
      expect(Kwh.fromDouble(2) >= Kwh.fromDouble(2), isTrue);
    });
  });

  group('Naira comparison', () {
    test('orders amounts', () {
      expect(Naira.fromNaira(100) < Naira.fromNaira(200), isTrue);
      expect(Naira.fromNaira(300) > Naira.fromNaira(200), isTrue);
      expect(Naira.zero.isZero, isTrue);
    });

    test('scales', () {
      expect((Naira.fromNaira(1000) * 1.1).format(), '₦1,100');
    });
  });
}

