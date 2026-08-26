import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';

/// Grid's splash.
///
/// Two rules shape this:
///
/// 1. **It must not delay first value.** The cold-start budget is 2 s on the
///    reference low-end device, and a splash that holds the user for its own
///    sake spends a budget the product needs. The app initialises *behind*
///    this, and the whole sequence is 1.2 s — long enough to read as
///    deliberate, short enough that nobody waits on it.
/// 2. **It must not flash.** The native launch screens paint the same warm
///    black, so there is no white frame between the OS handing over and this
///    appearing.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  /// The full sequence, mark through wordmark to exit.
  static const Duration total = Duration(milliseconds: 1200);

  /// How long to hold when the platform has animations switched off.
  ///
  /// Shorter, because there is nothing to watch — but not zero. Someone who
  /// turns off animations still gets to see what they opened.
  static const Duration reducedTotal = Duration(milliseconds: 600);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashScreen.total,
  );

  // The mark arrives first, with a little overshoot so it lands rather than
  // simply appearing.
  late final Animation<double> _markScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.42, curve: Curves.easeOutBack),
  );
  late final Animation<double> _markFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.30, curve: Curves.easeOut),
  );

  // The glow follows it out, so the mark reads as lit rather than drawn.
  late final Animation<double> _glow = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.12, 0.62, curve: Curves.easeOutCubic),
  );

  // Then the name, rising slightly.
  late final Animation<double> _wordFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.34, 0.66, curve: Curves.easeOut),
  );
  late final Animation<double> _lineFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.48, 0.80, curve: Curves.easeOut),
  );

  Timer? _exit;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The splash's lifetime is a timer, not the animation.
    //
    // When the platform reports animations disabled — an accessibility
    // setting, and the default on a fresh simulator — Flutter completes every
    // AnimationController instantly. Hanging the dismissal off
    // `forward().whenComplete(...)` therefore tore the splash down before it
    // had drawn a single frame, on exactly the devices whose owners had asked
    // for less motion rather than none of the app.
    _exit ??= Timer(
      MediaQuery.disableAnimationsOf(context)
          ? SplashScreen.reducedTotal
          : SplashScreen.total,
      widget.onFinished,
    );
  }

  @override
  void dispose() {
    _exit?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    // Reduce-motion gets the same composition, held still. The sequence still
    // ends on time, so the app is never slower for turning motion off.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: c.surface,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final glow = reduceMotion ? 1.0 : _glow.value;
          return DecoratedBox(
            // A warm bloom behind the mark, so the screen is lit from within
            // rather than being a flat sheet with a logo on it.
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.15),
                radius: 0.5 + glow * 0.75,
                colors: [
                  c.brand.withValues(alpha: 0.20 * glow),
                  c.gradientEnd.withValues(alpha: 0.07 * glow),
                  c.surface,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: reduceMotion ? 1 : _markFade.value,
                    child: Transform.scale(
                      scale: reduceMotion ? 1 : 0.82 + _markScale.value * 0.18,
                      child: _Mark(glow: glow),
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  Opacity(
                    opacity: reduceMotion ? 1 : _wordFade.value,
                    child: Transform.translate(
                      offset: Offset(
                        0,
                        reduceMotion ? 0 : (1 - _wordFade.value) * 10,
                      ),
                      child: Text(
                        'Grid',
                        style: t.display.copyWith(
                          letterSpacing: -0.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Opacity(
                    opacity: reduceMotion ? 1 : _lineFade.value,
                    child: Text(
                      'Know what your power costs',
                      style: t.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The brand mark: the bolt on the hero gradient, same as the payoff screen.
class _Mark extends StatelessWidget {
  const _Mark({required this.glow});

  final double glow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        gradient: c.heroGradient,
        borderRadius: Radii.xlAll,
        boxShadow: [
          BoxShadow(
            color: c.gradientEnd.withValues(alpha: 0.45 * glow),
            blurRadius: 40 * glow,
            spreadRadius: 4 * glow,
          ),
        ],
      ),
      child: Icon(Icons.bolt_rounded, size: 52, color: c.onBrand),
    );
  }
}
