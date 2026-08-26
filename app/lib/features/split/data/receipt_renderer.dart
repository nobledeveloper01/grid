import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../domain/entities/meter.dart';
import '../../../domain/services/allocation_engine.dart';

/// One occupant's share, as a document.
///
/// The argument this settles happens on WhatsApp, so the receipt has to be a
/// file somebody can forward — and it has to show the arithmetic rather than
/// the answer, because the answer alone is what everyone is already
/// disagreeing about.
class ReceiptRenderer {
  const ReceiptRenderer();

  static const _ink = PdfColor.fromInt(0xFF14110C);
  static const _muted = PdfColor.fromInt(0xFF6B6255);
  static const _rule = PdfColor.fromInt(0xFFD8D0C4);
  static const _accent = PdfColor.fromInt(0xFF8A5A00);
  static const _wash = PdfColor.fromInt(0xFFF6F1E8);

  Future<Uint8List> render({
    required Allocation allocation,
    required Share share,
    required Meter meter,
  }) async {
    final regular =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Inter.ttf'));
    final mono =
        pw.Font.ttf(await rootBundle.load('assets/fonts/RobotoMono.ttf'));

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: regular,
        italic: regular,
      ).copyWith(
        defaultTextStyle: pw.TextStyle(font: regular, fontSize: 10),
        tableCell: pw.TextStyle(font: mono, fontSize: 9),
      ),
      title: '${share.occupant.name} — electricity share',
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('ELECTRICITY SHARE',
                style: pw.TextStyle(
                    fontSize: 8, color: _accent, letterSpacing: 1.4)),
            pw.SizedBox(height: 4),
            pw.Text(share.occupant.name,
                style: pw.TextStyle(fontSize: 20, color: _ink)),
            pw.Text(
              '${_date(allocation.periodStart)} to '
              '${_date(allocation.periodEnd)}',
              style: const pw.TextStyle(fontSize: 10, color: _muted),
            ),
            pw.SizedBox(height: 14),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(color: _wash),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(share.amount.formatTight(),
                      style: pw.TextStyle(fontSize: 24, color: _ink)),
                  pw.SizedBox(height: 2),
                  pw.Text('${share.energy.format()} of the meter total',
                      style: const pw.TextStyle(fontSize: 10, color: _muted)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text('HOW THIS WAS WORKED OUT',
                style: pw.TextStyle(
                    fontSize: 8, color: _accent, letterSpacing: 1.2)),
            pw.SizedBox(height: 6),
            pw.Text(
              '${allocation.rule.label}. ${allocation.rule.description}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: const ['Household', 'Basis', 'Share'],
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
                for (final s in allocation.shares)
                  [
                    s.occupant.name,
                    _basis(allocation.rule, s),
                    s.amount.formatTight(),
                  ],
                [
                  'Meter total',
                  '',
                  allocation.total.formatTight(),
                ],
              ],
            ),
            pw.SizedBox(height: 10),
            // The line that stops the argument: the shares add up, and the
            // reader can check it against the row above without a calculator.
            pw.Text(
              allocation.sumsExactly
                  ? 'The shares add up to the meter total exactly.'
                  : 'These shares do not sum to the total — do not use this.',
              style: pw.TextStyle(
                fontSize: 9,
                color: allocation.sumsExactly ? _muted : _ink,
              ),
            ),
            if (allocation.remainderGivenTo != null) ...[
              pw.SizedBox(height: 3),
              pw.Text(
                'A few kobo could not be divided evenly and were added to '
                "${allocation.remainderGivenTo}'s share.",
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
            ],
            pw.Spacer(),
            pw.Divider(color: _rule),
            pw.Text(
              'Meter ${meter.meterNumber ?? meter.label} · '
              '${meter.disco.label}. Prepared with Grid from readings taken '
              'at the meter.',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  String _basis(SplitRule rule, Share s) => switch (rule) {
        SplitRule.equal => 'equal',
        SplitRule.byRooms =>
          '${s.occupant.rooms} ${s.occupant.rooms == 1 ? 'room' : 'rooms'}',
        SplitRule.byLoad => '${s.basis.round()} units',
        SplitRule.manual => s.basis.toStringAsFixed(0),
      };

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
}
