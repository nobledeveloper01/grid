import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../domain/services/band_adherence_engine.dart';
import '../../../domain/value_objects/enums.dart';
import '../../../domain/services/dispute_pack_engine.dart';

/// Turns a [DisputePack] into a PDF.
///
/// This layer adds no figures and no caveats. Everything printed here was
/// decided by `DisputePackEngine`, where it is testable — a renderer that
/// computes anything is a renderer whose output nobody can assert against.
class PackRenderer {
  const PackRenderer();

  /// Fonts are embedded rather than relying on the built-in Helvetica, whose
  /// WinAnsi encoding has no naira sign. A pack that prints the amount in
  /// dispute as a blank rectangle is not a pack.
  static Future<pw.ThemeData> _theme() async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter.ttf'));
    final mono =
        pw.Font.ttf(await rootBundle.load('assets/fonts/RobotoMono.ttf'));
    return pw.ThemeData.withFont(base: regular, bold: regular, italic: regular)
        .copyWith(
      defaultTextStyle: pw.TextStyle(font: regular, fontSize: 10),
      tableCell: pw.TextStyle(font: mono, fontSize: 9),
    );
  }

  static const _ink = PdfColor.fromInt(0xFF14110C);
  static const _muted = PdfColor.fromInt(0xFF6B6255);
  static const _rule = PdfColor.fromInt(0xFFD8D0C4);
  static const _accent = PdfColor.fromInt(0xFF8A5A00);
  static const _wash = PdfColor.fromInt(0xFFF6F1E8);

  Future<Uint8List> render(DisputePack pack) async {
    final theme = await _theme();
    final doc = pw.Document(theme: theme, title: _title(pack));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        // A backstop, not the fix. The log is rolled up by period length so
        // a normal pack is a handful of pages; this exists so an unforeseen
        // record can never make the document fail to generate outright,
        // which is what the default limit of 20 did to a twelve-month pack.
        maxPages: 200,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
        header: (context) =>
            context.pageNumber == 1 ? pw.SizedBox() : _runningHead(pack),
        footer: _footer,
        build: (context) => [
          _masthead(pack),
          pw.SizedBox(height: 18),
          _facts(pack),
          pw.SizedBox(height: 18),
          if (pack.kind.isClaim) ...[
            _claim(pack),
            pw.SizedBox(height: 18),
          ],
          _coverage(pack),
          pw.SizedBox(height: 18),
          if (pack.narrative != null && pack.narrative!.trim().isNotEmpty) ...[
            _section('In the account holder’s own words'),
            pw.Text(pack.narrative!.trim()),
            pw.SizedBox(height: 18),
          ],
          // Spread rather than wrapped. A pw.Column cannot be split across
          // pages, so a table taller than one page inside one makes MultiPage
          // add pages forever — a twelve-month pack failed to generate at all
          // until these became top-level children that the layout can break.
          ..._readings(pack),
          if (pack.excluded.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            ..._exclusions(pack),
          ],
          if (pack.supplyBuckets.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            ..._supplyLog(pack),
          ],
          if (pack.worstDays.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            ..._worstDays(pack),
          ],
          if (pack.photoHashes.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            ..._hashes(pack),
          ],
          pw.SizedBox(height: 18),
          _method(pack),
        ],
      ),
    );

    return doc.save();
  }

  String _title(DisputePack p) =>
      '${p.kind.label} — ${p.meter.meterNumber ?? p.meter.label}';

  // --- pieces --------------------------------------------------------------

  pw.Widget _masthead(DisputePack pack) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            pack.kind.label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 9,
              color: _accent,
              letterSpacing: 1.4,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            pack.kind.isClaim
                ? 'Statement of complaint'
                : 'Statement of consumption',
            style: pw.TextStyle(fontSize: 22, color: _ink),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_date(pack.periodStart)} to ${_date(pack.periodEnd)} · '
            '${pack.days} days',
            style: const pw.TextStyle(fontSize: 11, color: _muted),
          ),
          pw.SizedBox(height: 10),
          pw.Divider(color: _rule, thickness: 1),
        ],
      );

  pw.Widget _runningHead(DisputePack pack) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _rule)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(pack.kind.label,
                style: const pw.TextStyle(fontSize: 9, color: _muted)),
            pw.Text(
              pack.meter.meterNumber ?? pack.meter.label,
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ],
        ),
      );

  pw.Widget _footer(pw.Context context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Prepared with Grid from a record kept on the account '
              'holder’s own device.',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
            pw.Text(
              '${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ],
        ),
      );

  pw.Widget _facts(DisputePack pack) {
    final m = pack.meter;
    final rows = <(String, String)>[
      ('Meter number', m.meterNumber ?? 'Not recorded'),
      ('Distribution company', m.disco.label),
      if (m.tariffBand != null) ('Tariff band', 'Band ${m.tariffBand!.label}'),
      ('Meter type', m.type.label),
      if (m.address != null) ('Address', m.address!),
      if (m.lga != null) ('LGA', m.lga!),
      ('Pack generated', '${_date(pack.generatedAt)} '
          '${_time(pack.generatedAt)}'),
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: const pw.BoxDecoration(color: _wash),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final (label, value) in rows)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 140,
                    child: pw.Text(label,
                        style: const pw.TextStyle(
                            fontSize: 9, color: _muted)),
                  ),
                  pw.Expanded(
                    child: pw.Text(value,
                        style: const pw.TextStyle(fontSize: 10, color: _ink)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _claim(DisputePack pack) {
    final lines = <String>[];
    final headline = switch (pack.kind) {
      PackKind.bandShortfall => _bandHeadline(pack, lines),
      PackKind.estimatedBill => _billHeadline(pack, lines),
      PackKind.prolongedOutage => _outageHeadline(pack, lines),
      PackKind.consumptionRecord => null,
    };

    if (headline == null) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _section('What is being disputed'),
        pw.Text(headline,
            style: pw.TextStyle(fontSize: 15, color: _ink)),
        pw.SizedBox(height: 8),
        // A hanging indent, so a wrapped bullet does not run back to the
        // margin and read as a new paragraph.
        for (final l in lines)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 14,
                  child: pw.Text('•',
                      style: const pw.TextStyle(fontSize: 10)),
                ),
                pw.Expanded(
                  child: pw.Text(l,
                      style: const pw.TextStyle(fontSize: 10)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String? _bandHeadline(DisputePack pack, List<String> lines) {
    final a = pack.adherence;
    switch (a) {
      case AdherenceShortfall():
        lines.add(
          'Band ${a.billedBand.label} carries a commitment of '
          '${a.billedBand.committedHours} hours of supply a day.',
        );
        lines.add(
          'This connection recorded an average of '
          '${a.measuredHours.toStringAsFixed(1)} hours a day across the '
          '${a.usableDays} days of the period that were measured well '
          'enough to count.',
        );
        if (a.deliveredBand != null) {
          lines.add(
            'That level of supply corresponds to Band '
            '${a.deliveredBand!.label}, not Band ${a.billedBand.label}.',
          );
        }
        if (a.overpayment != null && !a.overpayment!.isZero) {
          lines.add(
            'On ${a.energy.format()} consumed in the period, the difference '
            'between the Band ${a.billedBand.label} rate and the Band '
            '${a.deliveredBand!.label} rate is '
            '${a.overpayment!.formatTight()}.',
          );
          if (a.energyIsAllocated) {
            lines.add(
              'The energy figure is apportioned between readings taken '
              'inside the period rather than read at both ends of it.',
            );
          }
        }
        return 'Supply short of the Band ${a.billedBand.label} commitment by '
            '${a.shortfallHours.toStringAsFixed(1)} hours a day.';
      case AdherenceMet():
        return null;
      case AdherenceUnknown():
        return null;
      case null:
        return null;
    }
  }

  String? _billHeadline(DisputePack pack, List<String> lines) {
    final amount = pack.disputedAmount;
    lines.add(
      'The meter recorded ${pack.consumption.total.format()} over the '
      '${pack.days} days of this period.',
    );
    lines.add(
      'That figure is derived from ${pack.included.length} readings taken '
      'from the meter itself, listed in full below.',
    );
    if (amount == null) {
      return 'The bill for this period does not match the meter record.';
    }
    return 'A bill of ${amount.formatTight()} against a metered consumption of '
        '${pack.consumption.total.format()}.';
  }

  String? _outageHeadline(DisputePack pack, List<String> lines) {
    final usable = pack.supplyDays.where((d) => d.isUsable).toList();
    if (usable.isEmpty) return null;
    final totalHours =
        usable.fold<double>(0, (a, d) => a + d.hoursOn);
    final offHours = usable.length * 24 - totalHours;
    lines.add(
      'Across ${usable.length} days measured well enough to count, supply '
      'was present for ${totalHours.toStringAsFixed(0)} hours and absent '
      'for ${offHours.toStringAsFixed(0)}.',
    );
    lines.add(
      'The day-by-day log follows, with the proportion of each day actually '
      'observed stated against it.',
    );
    return 'A record of supply interruption over ${pack.days} days.';
  }

  /// The section that makes the rest of the document credible.
  pw.Widget _coverage(DisputePack pack) => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _rule),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('How complete this record is',
                style: pw.TextStyle(fontSize: 11, color: _ink)),
            pw.SizedBox(height: 6),
            pw.Text(
              'Meter readings span '
              '${(pack.readingCoverage * 100).round()}% of the period. '
              'The supply log observed '
              '${(pack.supplyCoverage * 100).round()}% of it. '
              'Time that was not observed is recorded as unknown and is left '
              'out of every average above — it is not filled in, and no '
              'figure in this document assumes what happened during it.',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ],
        ),
      );

  List<pw.Widget> _readings(DisputePack pack) {
    if (pack.evidence.isEmpty) return const [];
    return [
      _section('Meter readings in this period'),
      pw.TableHelper.fromTextArray(
          headers: const ['Date', 'Reading', 'How taken', 'Photo', 'In figures'],
          headerStyle: pw.TextStyle(fontSize: 9, color: _ink),
          headerDecoration: const pw.BoxDecoration(color: _wash),
          cellStyle: const pw.TextStyle(fontSize: 9),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.5),
          1: pw.FlexColumnWidth(1.3),
          2: pw.FlexColumnWidth(1.3),
          3: pw.FlexColumnWidth(0.7),
          4: pw.FlexColumnWidth(1.1),
          5: pw.FlexColumnWidth(2.6),
        },
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerRight,
          2: pw.Alignment.centerLeft,
          3: pw.Alignment.center,
          4: pw.Alignment.center,
          5: pw.Alignment.centerLeft,
        },
          border: pw.TableBorder.all(color: _rule, width: 0.5),
        data: [
          for (final e in pack.evidence)
            [
              _date(e.reading.readAt),
              e.reading.value.formatValue(),
              switch (e.reading.source) {
                ReadingSource.ocr => 'Photograph',
                ReadingSource.manual => 'Typed',
                ReadingSource.imported => 'Imported',
              },
              e.reading.photoSha256 == null ? '—' : 'Yes',
              e.isIncluded
                  ? (e.isFlagged ? 'Included, flagged' : 'Included')
                  : 'Excluded',
              e.note ?? '',
            ],
        ],
      ),
    ];
  }

  List<pw.Widget> _exclusions(DisputePack pack) => [
          _section('Readings excluded, and why'),
          pw.Text(
            'These readings remain part of the record. They are set aside '
            'from the averages above rather than deleted, and the reason for '
            'each is stated.',
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
          pw.SizedBox(height: 6),
          for (final e in pack.excluded)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 130,
                    child: pw.Text(
                      '${_date(e.reading.readAt)} · '
                      '${e.reading.value.formatValue()}',
                      style: const pw.TextStyle(fontSize: 9, color: _ink),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      e.exclusionReason ?? 'Flagged.',
                      style: const pw.TextStyle(fontSize: 9, color: _muted),
                    ),
                  ),
                ],
              ),
            ),
      ];

  List<pw.Widget> _supplyLog(DisputePack pack) {
    final rolled = pack.supplyDetail != SupplyDetail.daily;
    return [
        _section('${pack.supplyDetail.label} supply'),
        if (rolled)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text(
              'Averaged over the days in each period that were observed well '
              'enough to count. Days that were not observed are left out of '
              'the average rather than counted as no supply.',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ),
        pw.TableHelper.fromTextArray(
          headers: [
            rolled ? 'Period' : 'Date',
            'Hours with supply',
            rolled ? 'Days counted' : 'Day observed',
          ],
          headerStyle: pw.TextStyle(fontSize: 9, color: _ink),
          headerDecoration: const pw.BoxDecoration(color: _wash),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
          },
          border: pw.TableBorder.all(color: _rule, width: 0.5),
          data: [
            for (final b in pack.supplyBuckets.reversed)
              [
                b.label,
                b.isUsable
                    ? '${b.meanHoursPerDay.toStringAsFixed(1)}'
                        '${rolled ? ' a day' : ''}'
                    : 'not counted',
                rolled
                    ? '${b.usableDays} of ${b.totalDays}'
                    : '${(b.coverage * 100).round()}%',
              ],
          ],
        ),
    ];
  }

  /// A monthly average hides the days a complaint is actually about.
  List<pw.Widget> _worstDays(DisputePack pack) => [
          _section('The worst days on record'),
          pw.Text(
            'The observed days with the least supply, from the same log. '
            'Averages above are the pattern; these are the days themselves.',
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: const ['Date', 'Hours with supply', 'Day observed'],
            headerStyle: pw.TextStyle(fontSize: 9, color: _ink),
            headerDecoration: const pw.BoxDecoration(color: _wash),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
            },
            border: pw.TableBorder.all(color: _rule, width: 0.5),
            data: [
              for (final d in pack.worstDays)
                [
                  _date(d.date),
                  d.hoursOn.toStringAsFixed(1),
                  '${(d.coverage * 100).round()}%',
                ],
            ],
          ),
      ];

  List<pw.Widget> _hashes(DisputePack pack) => [
          _section('Photograph fingerprints'),
          pw.Text(
            'Each photograph kept with a reading has a SHA-256 fingerprint. '
            'If a photograph is produced later, this value shows whether it '
            'is the same image that was taken at the time.',
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
          pw.SizedBox(height: 6),
          for (final entry in pack.photoHashes.entries)
            pw.Text(
              '${entry.key}  ${entry.value}',
              style: const pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
      ];

  pw.Widget _method(DisputePack pack) => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: const pw.BoxDecoration(color: _wash),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('How these figures were produced',
                style: pw.TextStyle(fontSize: 11, color: _ink)),
            pw.SizedBox(height: 6),
            pw.Text(
              'Readings were entered by the account holder, by hand or by '
              'photographing the meter, on the dates shown. Consumption is '
              'the difference between consecutive readings. Supply hours '
              'come from a log kept on the account holder’s phone, which '
              'records when mains power was present and marks as unknown any '
              'period it did not observe. A reading, once entered, is never '
              'edited or removed: a correction is recorded as a new entry '
              'and the original is retained.',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ],
        ),
      );

  pw.Widget _section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(fontSize: 9, color: _accent, letterSpacing: 1.2),
        ),
      );

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}
