import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/services/band_adherence_engine.dart';
import '../../../domain/value_objects/enums.dart';

/// What the band promised, what arrived, and what the difference is worth.
///
/// Feature F4. The card has three states and renders all three — an
/// under-measured month gets the same prominence as a proven shortfall,
/// because the alternative is a card that appears only when it has bad news
/// and therefore cannot be trusted when it says nothing.
class BandAdherenceCard extends StatelessWidget {
  const BandAdherenceCard({super.key, required this.adherence});

  final BandAdherence adherence;

  @override
  Widget build(BuildContext context) {
    return switch (adherence) {
      AdherenceUnknown(:final coverage, :final usableDays, :final reason) =>
        _Shell(
          tone: _Tone.quiet,
          band: adherence.billedBand,
          windowDays: adherence.windowDays,
          child: _Unknown(
            coverage: coverage,
            usableDays: usableDays,
            reason: reason,
          ),
        ),
      AdherenceMet() => _Shell(
          tone: _Tone.good,
          band: adherence.billedBand,
          windowDays: adherence.windowDays,
          child: _Met(result: adherence as AdherenceMet),
        ),
      AdherenceShortfall() => _Shell(
          tone: _Tone.warn,
          band: adherence.billedBand,
          windowDays: adherence.windowDays,
          child: _Shortfall(result: adherence as AdherenceShortfall),
        ),
    };
  }
}

enum _Tone { quiet, good, warn }

class _Shell extends StatelessWidget {
  const _Shell({
    required this.tone,
    required this.band,
    required this.windowDays,
    required this.child,
  });

  final _Tone tone;
  final TariffBand band;
  final int windowDays;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    final accent = switch (tone) {
      _Tone.quiet => c.textTertiary,
      _Tone.good => c.supplyOn,
      _Tone.warn => c.warning,
    };

    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: Radii.lgAll,
        border: Border.all(
          color: tone == _Tone.warn ? c.warning.withValues(alpha: 0.35) : c.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'BAND ${band.label} · LAST $windowDays DAYS',
                  style: t.label.copyWith(
                    color: c.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          child,
        ],
      ),
    );
  }
}

/// Not enough measurement. Says what is missing and what would fix it,
/// because a dead end here reads as the app being broken.
class _Unknown extends StatelessWidget {
  const _Unknown({
    required this.coverage,
    required this.usableDays,
    required this.reason,
  });

  final double coverage;
  final int usableDays;
  final AdherenceGap reason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    final (what, next) = switch (reason) {
      AdherenceGap.tooFewUsableDays => (
          'Not enough days measured yet',
          'Grid has $usableDays ${usableDays == 1 ? 'day' : 'days'} with '
              'enough data. It needs '
              '${BandAdherenceEngine.minimumUsableDays} before an average '
              'means anything.',
        ),
      AdherenceGap.coverageTooLow => (
          'Not enough of the month measured',
          'This log covers ${formatPercent(coverage)} of the last 30 days. '
              'Below ${formatPercent(BandAdherenceEngine.minimumCoverage)}, '
              'an average is a guess — and a guess is exactly what a DisCo '
              'would take apart.',
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(what, style: t.headline.copyWith(color: c.textPrimary)),
        const SizedBox(height: Space.sm),
        Text(next, style: t.body.copyWith(color: c.textSecondary)),
      ],
    );
  }
}

class _Met extends StatelessWidget {
  const _Met({required this.result});

  final AdherenceMet result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatHours(result.measuredHours),
          style: t.display.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'a day, against the ${result.billedBand.committedHours} hours '
          'Band ${result.billedBand.label} promises.',
          style: t.body.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: Space.lg),
        _Bar(
          measured: result.measuredHours,
          committed: result.billedBand.committedHours.toDouble(),
        ),
        const SizedBox(height: Space.lg),
        _Coverage(coverage: result.coverage, usableDays: result.usableDays),
      ],
    );
  }
}

class _Shortfall extends StatelessWidget {
  const _Shortfall({required this.result});

  final AdherenceShortfall result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    final delivered = result.deliveredBand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatHours(result.measuredHours),
          style: t.display.copyWith(color: c.warning),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'a day. Band ${result.billedBand.label} promises '
          '${result.billedBand.committedHours} — you are '
          '${formatHours(result.shortfallHours)} short, '
          '${formatPercent(result.shortfallPercent)} below.',
          style: t.body.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: Space.lg),
        _Bar(
          measured: result.measuredHours,
          committed: result.billedBand.committedHours.toDouble(),
          tone: c.warning,
        ),
        const SizedBox(height: Space.lg),

        // The line that does the work. Stated as arithmetic the user can
        // repeat out loud, because they will have to.
        if (result.overpayment != null && !result.overpayment!.isZero) ...[
          Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              color: c.warningSoft,
              borderRadius: Radii.mdAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.overpayment!.format(),
                  style: t.headline.copyWith(color: c.warning),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'is the difference between what you paid at the Band '
                  '${result.billedBand.label} rate and what Band '
                  '${delivered!.label} service costs — over the '
                  '${result.energy.format()} you used this period.',
                  style: t.caption.copyWith(color: c.textSecondary),
                ),
                if (result.energyIsAllocated) ...[
                  const SizedBox(height: Space.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // A marker, not a paragraph. The disclosure has to be
                      // unmissable without out-shouting the figure it is
                      // qualifying — five lines of estimate-violet did the
                      // second thing and stopped doing the first.
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c.estimateSoft,
                          borderRadius: Radii.smAll,
                        ),
                        child: Text(
                          'APPORTIONED',
                          style: t.caption.copyWith(
                            color: c.estimate,
                            fontSize: 10,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          'Shared out between readings rather than read at '
                          'both ends of this window.',
                          style: t.caption.copyWith(color: c.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
        ] else if (result.isBelowLowestBand) ...[
          Text(
            'That is below every published band, so there is no rate to '
            'compare it against. The hours are the case here, not the money.',
            style: t.caption.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.lg),
        ],

        _Coverage(coverage: result.coverage, usableDays: result.usableDays),
      ],
    );
  }
}

/// Measured against committed, on one track. The committed mark stays visible
/// even when delivery exceeds it.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.measured,
    required this.committed,
    this.tone,
  });

  final double measured;
  final double committed;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final fill = tone ?? c.supplyOn;

    // Scaled to 24 hours, always, so the same shortfall looks the same size
    // on band A as on band E.
    const scale = 24.0;

    return Semantics(
      label: '${formatHours(measured)} measured against '
          '${committed.round()} hours committed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final markAt = (committed / scale).clamp(0.0, 1.0) * width;
              return SizedBox(
                height: 24,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 14,
                        width: width,
                        decoration: BoxDecoration(
                          color: c.track,
                          borderRadius: Radii.smAll,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 14,
                        width: (measured / scale).clamp(0.0, 1.0) * width,
                        decoration: BoxDecoration(
                          color: fill,
                          borderRadius: Radii.smAll,
                        ),
                      ),
                    ),
                    Positioned(
                      left: markAt - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: c.textPrimary),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: Space.xs),
          Text(
            'The line marks the ${committed.round()}-hour promise.',
            style: t.caption.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Coverage extends StatelessWidget {
  const _Coverage({required this.coverage, required this.usableDays});

  final double coverage;
  final int usableDays;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Text(
      'Measured across $usableDays usable '
      '${usableDays == 1 ? 'day' : 'days'}, covering '
      '${formatPercent(coverage)} of the period. Grid never fills in the '
      'gaps.',
      style: t.caption.copyWith(color: c.textTertiary),
    );
  }
}
