import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../meter/application/meter_providers.dart';
import '../application/capture_controller.dart';

/// The meter capture screen.
///
/// Full-bleed camera with a guide rect sized to the declared meter type's
/// register. Everything is reachable by a right thumb, torch on the left,
/// manual entry on the right — and manual entry is *always* one tap away,
/// because a dead end at a meter at night costs the reading.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _torchOn = false;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive) {
      if (controller == null) return;
      // Clear the field *before* disposing. A disposed CameraController keeps
      // reporting `value.isInitialized == true`, so leaving the reference in
      // place lets the next build hand a dead controller to CameraPreview.
      setState(() => _controller = null);
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null) _start();
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _failure = 'no_camera');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        // High rather than max: the guide rect crops most of the frame away,
        // and a smaller frame reaches the recogniser sooner. The 1500ms
        // budget is spent on recognition, not on encoding pixels we discard.
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFocusMode(FocusMode.auto);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      // Two _start() calls can overlap (lifecycle + initState). Whichever
      // finishes second must not orphan the first controller.
      final existing = _controller;
      setState(() {
        _controller = controller;
        _failure = null;
      });
      await existing?.dispose();
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.code == 'CameraAccessDenied' ? 'denied' : 'failed';
      });
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      setState(() => _torchOn = !_torchOn);
      await HapticFeedback.selectionClick();
    } on CameraException {
      // Some devices have no torch. Not worth an error — the button simply
      // stops responding, and the user can still capture.
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    final meter = ref.read(selectedMeterProvider);
    if (controller == null || meter == null || _busy) return;

    setState(() => _busy = true);
    await HapticFeedback.mediumImpact();

    try {
      final shot = await controller.takePicture();
      final result = await ref
          .read(captureControllerProvider.notifier)
          .process(file: File(shot.path), meter: meter);
      if (!mounted) return;
      context.pushReplacement(Routes.confirmReading, extra: result);
    } on CameraException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = 'failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (_failure != null) {
      return _CaptureUnavailable(reason: _failure!);
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Scaffold(
        backgroundColor: c.surfaceInverse,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller),
          const _GuideOverlay(),
          SafeArea(
            child: Column(
              children: [
                _TopBar(onClose: () => context.pop()),
                const Spacer(),
                const _Instruction(),
                const SizedBox(height: Space.xl),
                _Controls(
                  torchOn: _torchOn,
                  busy: _busy,
                  onTorch: _toggleTorch,
                  onCapture: _capture,
                  onManual: () =>
                      context.pushReplacement(Routes.manualEntry),
                ),
                const SizedBox(height: Space.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dims everything outside the register, so the user frames the digits
/// rather than the whole meter.
class _GuideOverlay extends StatelessWidget {
  const _GuideOverlay();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * 0.82;
        final height = width * 0.32;
        return Stack(
          children: [
            // The scrim, punched through where the guide sits.
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black54,
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: width,
                      height: height,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: Radii.mdAll,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Corner marks rather than a solid frame, so the digits stay
            // unobstructed.
            Center(
              child: SizedBox(
                width: width,
                height: height,
                child: CustomPaint(
                  painter: _CornerPainter(colour: context.colors.brand),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.colour});

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const arm = 22.0;

    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o.translate(arm * dx, 0), paint);
      canvas.drawLine(o, o.translate(0, arm * dy), paint);
    }

    corner(Offset.zero, 1, 1);
    corner(Offset(size.width, 0), -1, 1);
    corner(Offset(0, size.height), 1, -1);
    corner(Offset(size.width, size.height), -1, -1);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.colour != colour;
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.close_rounded,
            label: 'Close',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _Instruction extends StatelessWidget {
  const _Instruction();

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: Radii.mdAll,
        ),
        child: Text(
          'Line up the numbers inside the box',
          textAlign: TextAlign.center,
          style: t.bodyStrong.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.torchOn,
    required this.busy,
    required this.onTorch,
    required this.onCapture,
    required this.onManual,
  });

  final bool torchOn;
  final bool busy;
  final VoidCallback onTorch;
  final VoidCallback onCapture;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _CircleButton(
            icon: torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
            label: torchOn ? 'Turn torch off' : 'Turn torch on',
            active: torchOn,
            onPressed: onTorch,
          ),
          Semantics(
            button: true,
            label: 'Take the photo',
            child: GestureDetector(
              onTap: busy ? null : onCapture,
              child: Container(
                width: Targets.capture,
                height: Targets.capture,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.brand,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: Shadows.glow(c.brand),
                ),
                child: busy
                    ? Padding(
                        padding: const EdgeInsets.all(Space.xl),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: c.onBrand,
                        ),
                      )
                    : Icon(Icons.camera_alt_rounded, color: c.onBrand, size: 30),
              ),
            ),
          ),
          _CircleButton(
            icon: Icons.keyboard_rounded,
            label: 'Type the reading instead',
            onPressed: onManual,
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: Targets.outdoor,
            height: Targets.outdoor,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? c.brand : Colors.black.withValues(alpha: 0.55),
            ),
            child: Icon(
              icon,
              color: active ? c.onBrand : Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the camera is unavailable for any reason.
///
/// Never a dead end: manual entry is the primary action, and the copy says
/// what is lost rather than what went wrong.
class _CaptureUnavailable extends StatelessWidget {
  const _CaptureUnavailable({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    final (title, body) = switch (reason) {
      'denied' => (
          'Grid needs the camera to read your meter',
          "You can still type the reading in by hand — it takes a few seconds "
              "longer. Or allow camera access in Settings and Grid will read "
              "the digits for you.",
        ),
      'no_camera' => (
          'No camera on this device',
          'Type the reading in by hand instead.',
        ),
      _ => (
          "The camera didn't start",
          'Type the reading in by hand, and try the camera again next time.',
        ),
    };

    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(title: const Text('Log reading')),
      body: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Space.xl),
            Icon(Icons.no_photography_rounded, size: 40, color: c.textTertiary),
            const SizedBox(height: Space.lg),
            Text(title, style: t.headline),
            const SizedBox(height: Space.md),
            Text(body, style: t.body.copyWith(color: c.textSecondary)),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => context.pushReplacement(Routes.manualEntry),
              icon: const Icon(Icons.keyboard_rounded),
              label: const Text('Type the reading'),
            ),
            const SizedBox(height: Space.sm),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Not now'),
            ),
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }
}
