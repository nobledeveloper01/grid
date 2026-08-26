import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/providers.dart';
import '../../../domain/entities/meter.dart';
import '../../../domain/services/digit_extractor.dart';

/// What a capture produced.
///
/// The photograph is always present; the reading may not be. That asymmetry
/// is deliberate — the photograph *is* the evidence, and OCR is only a
/// convenience on top of it (FR-2.2).
class CaptureResult {
  const CaptureResult({
    required this.meterId,
    required this.photoPath,
    required this.photoSha256,
    required this.elapsed,
    this.reading,
  });

  final String meterId;

  /// App-private path. Retained whether recognition succeeded or not.
  final String photoPath;

  /// Integrity anchor, so a dispute pack can show the photograph has not
  /// been swapped since it was taken.
  final String photoSha256;

  /// How long recognition actually took, against the 1500ms budget.
  final Duration elapsed;

  final ExtractedReading? reading;

  bool get recognised => reading != null && reading!.isUsable;

  /// True when recognition ran but produced nothing worth pre-filling. The
  /// confirm screen says so plainly rather than showing an empty field.
  bool get attemptedAndFailed => reading == null || !reading!.isUsable;
}

/// Captures, stores and recognises.
class CaptureController extends Notifier<void> {
  @override
  void build() {}

  /// Photographs live in the app-private documents directory, referenced by
  /// path from the reading row — never as blobs in the database, which would
  /// destroy query performance and backup size.
  static const String _folder = 'reading_photos';

  Future<CaptureResult> process({
    required File file,
    required Meter meter,
  }) async {
    final stored = await _store(file);
    final bytes = await stored.readAsBytes();
    final digest = sha256.convert(bytes).toString();

    final watch = Stopwatch()..start();
    final reading = await ref.read(textRecogniserProvider).readDigits(
          stored.path,
          meterType: meter.type,
          expectedDigitCount: meter.digitCount,
        );
    watch.stop();

    return CaptureResult(
      meterId: meter.id,
      photoPath: stored.path,
      photoSha256: digest,
      elapsed: watch.elapsed,
      reading: reading,
    );
  }

  /// Moves the camera's temporary file somewhere durable.
  Future<File> _store(File source) async {
    final dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, _folder),
    );
    if (!dir.existsSync()) await dir.create(recursive: true);

    final name = '${ref.read(uuidProvider).v7()}.jpg';
    final target = File(p.join(dir.path, name));
    await source.copy(target.path);

    // The camera plugin's temp file is ours to clean up.
    try {
      await source.delete();
    } on FileSystemException {
      // Not worth failing a capture over.
    }
    return target;
  }

  /// Discards a photograph the user abandoned, so cancelled captures do not
  /// accumulate on a device that is usually short of space.
  Future<void> discard(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Ignore.
    }
  }
}

final captureControllerProvider =
    NotifierProvider<CaptureController, void>(CaptureController.new);

/// Base64 of a photograph, for embedding in a dispute pack later.
Future<String> encodePhoto(String path) async =>
    base64Encode(await File(path).readAsBytes());
