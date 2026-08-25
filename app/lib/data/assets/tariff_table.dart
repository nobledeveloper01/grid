import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/value_objects/enums.dart';
import '../../domain/value_objects/units.dart';

/// The bundled tariff table.
///
/// Ships inside the binary so onboarding and every calculation work on a
/// device that has never touched a network. A newer version can be fetched
/// when connectivity exists, but a stale table never blocks anything — the
/// app simply displays the effective date of the rates it is using.
class TariffTable {
  const TariffTable({
    required this.version,
    required this.effectiveDate,
    required this.rates,
    required this.committedHours,
  });

  final int version;
  final DateTime effectiveDate;

  /// DisCo name -> band label -> kobo per kWh.
  final Map<String, Map<String, int>> rates;

  /// Band label -> committed daily supply hours.
  final Map<String, int> committedHours;

  static const String assetPath = 'assets/data/tariff_table.json';

  static Future<TariffTable> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return TariffTable.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  factory TariffTable.fromJson(Map<String, dynamic> json) {
    final bands = (json['bands'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as Map<String, dynamic>)['committedHours'] as int),
    );
    final rates = (json['rates'] as Map<String, dynamic>).map(
      (disco, byBand) => MapEntry(
        disco,
        (byBand as Map<String, dynamic>)
            .map((band, kobo) => MapEntry(band, kobo as int)),
      ),
    );
    return TariffTable(
      version: json['version'] as int,
      effectiveDate: DateTime.parse(json['effectiveDate'] as String),
      rates: rates,
      committedHours: bands,
    );
  }

  /// The published rate for a DisCo and band, or null if unknown.
  Rate? rateFor(DisCo disco, TariffBand band) {
    final kobo = rates[disco.name]?[band.label];
    return kobo == null ? null : Rate.fromKobo(kobo);
  }

  /// The rate actually used for a meter: a manual override always wins,
  /// then the published table, then null.
  Rate? effectiveRate({
    required DisCo disco,
    required TariffBand? band,
    required Rate? override,
  }) {
    if (override != null) return override;
    if (band == null) return null;
    return rateFor(disco, band);
  }

  /// Estimates a band from observed daily supply hours, for users who do not
  /// know theirs. Always presented as an estimate.
  TariffBand estimateBand(double dailySupplyHours) {
    for (final band in TariffBand.values) {
      if (dailySupplyHours >= band.committedHours) return band;
    }
    return TariffBand.e;
  }
}
