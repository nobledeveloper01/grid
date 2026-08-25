import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../domain/entities/meter.dart';
import '../../../domain/value_objects/enums.dart';

/// What the user has chosen so far during onboarding.
///
/// Held in memory only: nothing is written until there is a whole meter to
/// write, so an abandoned onboarding leaves no partial rows behind.
class OnboardingDraft {
  const OnboardingDraft({this.type, this.disco, this.band, this.label});

  final MeterType? type;
  final DisCo? disco;
  final TariffBand? band;
  final String? label;

  OnboardingDraft copyWith({
    MeterType? type,
    DisCo? disco,
    TariffBand? band,
    String? label,
  }) =>
      OnboardingDraft(
        type: type ?? this.type,
        disco: disco ?? this.disco,
        band: band ?? this.band,
        label: label ?? this.label,
      );

  bool get isComplete => type != null && disco != null;
}

class OnboardingController extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() => const OnboardingDraft();

  void setType(MeterType type) => state = state.copyWith(type: type);
  void setDisco(DisCo disco) => state = state.copyWith(disco: disco);
  void setBand(TariffBand? band) =>
      state = OnboardingDraft(
        type: state.type,
        disco: state.disco,
        band: band,
        label: state.label,
      );

  /// Creates the meter. This is the first database write in the app's life,
  /// and it happens without an account, without a network, and without the
  /// user having been asked who they are.
  Future<String> commit() async {
    final draft = state;
    final id = ref.read(uuidProvider).v7();
    final meter = Meter(
      id: id,
      label: draft.label ?? 'Home',
      type: draft.type ?? MeterType.postpaidDigital,
      disco: draft.disco ?? DisCo.other,
      createdAt: ref.read(clockProvider)(),
      tariffBand: draft.band,
      // Charging state stops tracking mains availability the moment there is
      // an inverter in the way, so we do not enable inference for a user who
      // told us they have no meter to read either.
      supplyDetectionEnabled: draft.type?.isReadable ?? true,
    );
    await ref.read(meterRepositoryProvider).save(meter);
    return id;
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingDraft>(
  OnboardingController.new,
);
