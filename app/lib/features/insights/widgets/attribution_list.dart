import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/services/load_model_engine.dart';

/// Modelled load attribution.
///
/// Every number here is an estimate and the widget is built so that cannot be
/// forgotten: the heading says modelled, the figures carry the `estimate`
/// tint, and the reconciliation against the meter is shown whether it
/// flatters the model or not.
class AttributionList extends StatelessWidget {
  const AttributionList({
    super.key,
    required this.model,
    required this.hasMeasuredSupply,
  });

  final LoadModel model;

  /// False when supply hours were not measured well enough to cap the model,
  /// in which case it assumed power was on all day and will read high.
  final bool hasMeasuredSupply;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    final divergence = model.divergence;
    final measured = model.measuredDailyTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: c.estimateSoft,
                borderRadius: Radii.smAll,
              ),
              child: Text(
                'MODELLED',
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
                'From what you told Grid you run — not from the meter.',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),

        for (final a in model.attributions)
          _Row(attribution: a, estimateColour: c.estimate),

        const SizedBox(height: Space.lg),

        // Reconciliation. Shown whether or not it flatters the model — a
        // model that only reports itself when it agrees with the meter is
        // not a model, it is a decoration.
        Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: c.surfaceDim,
            borderRadius: Radii.mdAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Model against meter',
                style: t.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Space.sm),
              if (measured == null)
                Text(
                  'Log a few more readings and Grid can check this model '
                  'against what the meter actually recorded.',
                  style: t.caption.copyWith(color: c.textTertiary),
                )
              else
                Text.rich(
                  TextSpan(
                    style: t.body.copyWith(color: c.textSecondary),
                    children: [
                      const TextSpan(text: 'The model adds up to '),
                      TextSpan(
                        text: model.modelledDailyTotal.format(),
                        style: t.bodyStrong.copyWith(color: c.estimate),
                      ),
                      const TextSpan(text: ' a day. The meter says '),
                      TextSpan(
                        text: measured.format(),
                        style: t.bodyStrong.copyWith(color: c.textPrimary),
                      ),
                      TextSpan(
                        text: divergence == null
                            ? '.'
                            : ' — ${_gap(divergence)}.',
                      ),
                    ],
                  ),
                  textScaler: MediaQuery.textScalerOf(context),
                ),
              if (!hasMeasuredSupply) ...[
                const SizedBox(height: Space.sm),
                Text(
                  'Grid has not measured your supply hours yet, so the model '
                  'assumed power was on all day. It will read high until the '
                  'power log fills in.',
                  style: t.caption.copyWith(color: c.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _gap(double divergence) {
    final pct = formatPercent(divergence.abs());
    if (divergence.abs() < 0.10) return 'close enough to agree';
    return divergence > 0
        ? '$pct more than the meter, so something is running less than you '
            'think'
        : '$pct less than the meter, so something is drawing power that is '
            'not on this list';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.attribution, required this.estimateColour});

  final ApplianceAttribution attribution;
  final Color estimateColour;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final a = attribution.appliance;

    return Semantics(
      label: '${a.name}, an estimated '
          '${formatPercent(attribution.share)} of daily use',
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    a.quantity > 1 ? '${a.name} ×${a.quantity}' : a.name,
                    style: t.body.copyWith(color: c.textPrimary),
                  ),
                ),
                Flexible(
                  child: Text(
                    attribution.modelledDaily.format(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.copyWith(color: estimateColour),
                  ),
                ),
                const SizedBox(width: Space.md),
                Text(
                  formatPercent(attribution.share),
                  textAlign: TextAlign.right,
                  style: t.caption.copyWith(color: c.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            ClipRRect(
              borderRadius: Radii.smAll,
              child: LinearProgressIndicator(
                value: attribution.share.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: c.track,
                // Dashed is not available on a progress bar, so the estimate
                // tint carries the distinction here. Colour is never the only
                // carrier: the MODELLED chip above and the per-row kWh figure
                // in the same tint both say it in words.
                valueColor: AlwaysStoppedAnimation(estimateColour),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
