import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/services/backup_engine.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../../shared/widgets/text_prompt_sheet.dart';
import '../application/backup_providers.dart';

/// Backup and restore.
///
/// Feature F13, and the least glamorous thing in the backlog. Grid holds two
/// years of evidence in a local database with no server behind it; an evidence
/// product with no recovery path is one dropped phone away from having nothing.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return GridScaffold(
      title: 'Backup',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          Text(
            'Everything Grid holds lives on this phone and nowhere else. A '
            'backup is the only thing standing between a lost handset and a '
            'lost record.',
            style: t.body.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.xl),

          _Action(
            icon: Icons.archive_outlined,
            title: 'Make a backup',
            subtitle: 'One encrypted file you can keep anywhere — Files, '
                'Drive, or a message to yourself.',
            onTap: _busy ? null : _backup,
          ),
          const SizedBox(height: Space.md),
          _Action(
            icon: Icons.settings_backup_restore_rounded,
            title: 'Restore from a backup',
            subtitle: 'Grid shows you what is in the archive before any of it '
                'touches your record.',
            onTap: _busy ? null : _restore,
          ),

          if (_message != null) ...[
            const SizedBox(height: Space.lg),
            InfoNote(
              tone: _isError ? NoteTone.warning : NoteTone.neutral,
              message: _message!,
            ),
          ],

          const SizedBox(height: Space.xl),
          Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              color: c.surfaceDim,
              borderRadius: Radii.mdAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What you should know',
                    style: t.label.copyWith(color: c.textSecondary)),
                const SizedBox(height: Space.sm),
                Text(
                  '· The file is encrypted with a passphrase you choose. '
                  'Grid does not keep it, and there is no way to recover it — '
                  'forget the passphrase and the archive is gone.\n'
                  '· Photographs are not carried in the archive. The readings '
                  'and their fingerprints are; the images stay on the phone '
                  'that took them.\n'
                  '· Restoring adds to your record rather than replacing it. '
                  'Restoring the same archive twice changes nothing.',
                  style: t.caption.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xxxl),
        ],
      ),
    );
  }

  Future<void> _backup() async {
    final passphrase = await promptForText(
      context,
      title: 'Choose a passphrase',
      description: 'You will need this exact phrase to restore. Grid cannot '
          'recover it for you — write it somewhere that is not this phone.',
      hintText: 'Four or five words you will remember',
      confirmLabel: 'Make the backup',
      capitalise: false,
    );
    if (passphrase == null || passphrase.trim().length < 8) {
      if (passphrase != null && mounted) {
        setState(() {
          _isError = true;
          _message = 'That passphrase is too short to be worth encrypting '
              'with. Use at least eight characters.';
        });
      }
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await ref
          .read(backupControllerProvider.notifier)
          .create(passphrase: passphrase.trim());
      if (!mounted) return;

      setState(() {
        _isError = false;
        _message = '${result.factCount} records, '
            '${(result.bytes / 1024).round()} KB. Send it somewhere that is '
            'not this phone.';
      });

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.path)],
          subject: 'Grid backup',
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = 'The backup did not finish: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    // No file picker in the dependency set, and adding one for this would be
    // a plugin on every platform for a flow used once. The archive is text,
    // so pasting it works — and works from a WhatsApp message, which is where
    // most of these will actually live.
    final envelope = await promptForText(
      context,
      title: 'Paste the backup',
      description: 'Open the .gridbak file, copy everything in it, and paste '
          'it here. It is one long line of text.',
      hintText: '{"header":{"magic":"GRIDBAK1"...',
      confirmLabel: 'Next',
      capitalise: false,
      maxLines: 4,
    );
    if (envelope == null || envelope.trim().isEmpty) return;

    if (!mounted) return;
    final passphrase = await promptForText(
      context,
      title: 'The passphrase',
      description: 'The one you chose when the backup was made.',
      confirmLabel: 'Open it',
      capitalise: false,
    );
    if (passphrase == null || passphrase.isEmpty) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    final outcome = await ref
        .read(backupControllerProvider.notifier)
        .inspect(envelope: envelope.trim(), passphrase: passphrase);

    if (!mounted) return;
    setState(() => _busy = false);

    switch (outcome) {
      case RestoreRefused(:final detail):
        setState(() {
          _isError = true;
          _message = detail;
        });
      case RestoreReady(:final archive, :final integrity):
        final confirmed = await _confirm(archive, integrity);
        if (confirmed != true || !mounted) return;

        setState(() => _busy = true);
        final count = await ref
            .read(backupControllerProvider.notifier)
            .apply(archive);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _isError = false;
          _message = '$count records restored.';
        });
    }
  }

  /// Shows what is in the archive before any of it is written.
  ///
  /// A restore that has already half-run is not something anyone can undo,
  /// so the decision point comes first.
  Future<bool?> _confirm(BackupArchive archive, List<String> integrity) {
    final t = context.type;
    final c = context.colors;

    return showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Restore this?', style: t.headline),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Made ${archive.createdAt.toIso8601String().split('T').first}.',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
              const SizedBox(height: Space.md),
              _Line('${archive.meters.length} meters'),
              _Line('${archive.readings.length} readings'),
              _Line('${archive.supply.length} supply events'),
              _Line('${archive.purchases.length} purchases'),
              if (archive.generators.isNotEmpty)
                _Line('${archive.generators.length} generators, '
                    '${archive.fuel.length} fuel purchases'),
              const SizedBox(height: Space.md),
              Text(
                'This adds to what is already here. Nothing is replaced or '
                'deleted.',
                style: t.caption.copyWith(color: c.textSecondary),
              ),
              if (integrity.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Text('WHAT DID NOT VERIFY',
                    style: t.caption.copyWith(
                        color: c.warning, letterSpacing: 0.6, fontSize: 10)),
                const SizedBox(height: Space.xs),
                for (final line in integrity.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('· $line',
                        style: t.caption.copyWith(color: c.textTertiary)),
                  ),
                if (integrity.length > 5)
                  Text('· and ${integrity.length - 5} more',
                      style: t.caption.copyWith(color: c.textTertiary)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text,
            style: context.type.body
                .copyWith(color: context.colors.textPrimary)),
      );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final enabled = onTap != null;

    return Material(
      color: c.surfaceRaised,
      borderRadius: Radii.mdAll,
      child: InkWell(
        borderRadius: Radii.mdAll,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Space.lg),
          constraints: const BoxConstraints(minHeight: Targets.min),
          decoration: BoxDecoration(
            borderRadius: Radii.mdAll,
            border: Border.all(color: c.outline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  size: 20,
                  color: enabled ? c.brand : c.textTertiary),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: t.body.copyWith(
                            color: enabled ? c.textPrimary : c.textTertiary)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: t.caption.copyWith(color: c.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
