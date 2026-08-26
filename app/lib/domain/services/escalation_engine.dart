/// The path a complaint takes, and where it has got to.
///
/// A dispute pack is a document. What a household actually needs is the
/// sequence: who to give it to, how long to wait before the next step, and
/// what to say when they get there. Most complaints die at step one, not
/// because the case was weak but because nobody knew there was a step two.
///
/// The waiting periods below are the engine's own defaults and are written
/// where they can be changed in one place. **Before this ships, each step
/// and each interval must be checked against the customer-complaints
/// regulation currently in force** — a Grid letter citing a superseded
/// procedure would damage the user's case, which is the one thing this
/// product exists not to do. See the phase 5 exit gate.
library;

enum EscalationStep {
  /// The office that issued the bill.
  businessUnit(
    'Business unit',
    'Take the pack to the office that issued the bill. Ask for a written '
        'acknowledgement with a date on it — the clock for every later step '
        'starts from that date, and without it you are starting again.',
    waitDays: 15,
  ),

  /// The DisCo's own complaints unit above the local office.
  discoComplaints(
    // Reads as a label and mid-sentence: "…before the DisCo complaints unit
    // opens". "The DisCo's complaints unit" did not.
    'DisCo complaints unit',
    'If the business unit has not resolved it, the complaint goes above the '
        'local office. Send the same pack, plus the acknowledgement, plus a '
        'line saying how long it has been.',
    waitDays: 15,
  ),

  /// The regulator's forum office for the area.
  forumOffice(
    'NERC Forum Office',
    'The forum office hears complaints the DisCo has not resolved. Bring the '
        'pack and every acknowledgement. This is a hearing, not a counter — '
        'the record is what it runs on.',
    waitDays: 30,
  ),

  /// The regulator itself, on review of a forum decision.
  commission(
    'The Commission',
    'A forum decision can be taken to the Commission for review. This is the '
        'last step, and it is the one where a complete, dated, consistent '
        'record matters most.',
    waitDays: null,
  );

  const EscalationStep(this.label, this.guidance, {required this.waitDays});

  final String label;
  final String guidance;

  /// How long to allow this step before the next becomes available. Null at
  /// the end of the ladder.
  final int? waitDays;

  EscalationStep? get next {
    final i = EscalationStep.values.indexOf(this);
    return i + 1 < EscalationStep.values.length
        ? EscalationStep.values[i + 1]
        : null;
  }
}

enum CaseStatus { open, awaitingResponse, resolved, abandoned }

/// Where a case stands, and what it is waiting for.
class EscalationState {
  const EscalationState({
    required this.step,
    required this.status,
    required this.submittedAt,
    required this.daysElapsed,
    required this.daysRemaining,
    required this.canEscalate,
  });

  final EscalationStep step;
  final CaseStatus status;

  /// When this step was submitted. Null if it has not been.
  final DateTime? submittedAt;

  /// Days since submission, or null if not submitted.
  final int? daysElapsed;

  /// Days left before the next step opens. Zero once it has opened; null
  /// where there is no next step or nothing has been submitted.
  final int? daysRemaining;

  /// Whether the next step is available now.
  final bool canEscalate;
}

class EscalationEngine {
  const EscalationEngine();

  EscalationState evaluate({
    required EscalationStep step,
    required CaseStatus status,
    required DateTime? submittedAt,
    required DateTime now,
  }) {
    if (submittedAt == null || status == CaseStatus.resolved ||
        status == CaseStatus.abandoned) {
      return EscalationState(
        step: step,
        status: status,
        submittedAt: submittedAt,
        daysElapsed: null,
        daysRemaining: null,
        canEscalate: false,
      );
    }

    final elapsed = now.difference(submittedAt).inDays;
    final wait = step.waitDays;

    if (wait == null || step.next == null) {
      return EscalationState(
        step: step,
        status: status,
        submittedAt: submittedAt,
        daysElapsed: elapsed,
        daysRemaining: null,
        canEscalate: false,
      );
    }

    final remaining = wait - elapsed;
    return EscalationState(
      step: step,
      status: status,
      submittedAt: submittedAt,
      daysElapsed: elapsed,
      daysRemaining: remaining < 0 ? 0 : remaining,
      canEscalate: remaining <= 0,
    );
  }
}
