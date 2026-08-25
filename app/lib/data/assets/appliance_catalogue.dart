import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// A catalogue entry: a starting point for an appliance, not a measurement.
class CatalogueAppliance {
  const CatalogueAppliance({
    required this.key,
    required this.name,
    required this.watts,
    required this.hours,
    required this.mainsOnly,
  });

  final String key;
  final String name;
  final int watts;
  final double hours;
  final bool mainsOnly;
}

/// The bundled appliance catalogue, chosen for this market rather than
/// inherited from a Western default list.
class ApplianceCatalogue {
  const ApplianceCatalogue(this.entries);

  final List<CatalogueAppliance> entries;

  static const String assetPath = 'assets/data/appliance_catalogue.json';

  static Future<ApplianceCatalogue> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return ApplianceCatalogue([
      for (final e in json['appliances'] as List<dynamic>)
        CatalogueAppliance(
          key: e['key'] as String,
          name: e['name'] as String,
          watts: e['watts'] as int,
          hours: (e['hours'] as num).toDouble(),
          mainsOnly: e['mainsOnly'] as bool,
        ),
    ]);
  }

  CatalogueAppliance? byKey(String key) {
    for (final e in entries) {
      if (e.key == key) return e;
    }
    return null;
  }
}
