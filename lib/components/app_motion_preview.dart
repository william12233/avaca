import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class AppMotionPreview extends StatefulWidget {
  const AppMotionPreview({
    super.key,
    required this.animate,
    required this.radius,
  });

  final bool animate;
  final BorderRadius radius;

  @override
  State<AppMotionPreview> createState() => _AppMotionPreviewState();
}

class _AppMotionPreviewState extends State<AppMotionPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AppLifecycleListener _lifecycle;
  bool _routeVisible = true;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _updatePlayback();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeVisible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _updatePlayback();
  }

  @override
  void didUpdateWidget(AppMotionPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) _loop.value = 0;
    _updatePlayback();
  }

  void _updatePlayback() {
    if (widget.animate && _foreground && _routeVisible) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('appearance-motion-sample'),
      label: widget.animate
          ? l10n.motionPreviewPlaying
          : l10n.motionPreviewStill,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: widget.radius,
            child: SizedBox(
              height: 104,
              child: CustomPaint(
                painter: _MotionDiagram(
                  scheme: scheme,
                  loop: widget.animate ? _loop : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MotionDiagram extends CustomPainter {
  _MotionDiagram({required this.scheme, required this.loop})
    : super(repaint: loop);

  final ColorScheme scheme;
  final Animation<double>? loop;
  static const _windowRadius = 10.0;

  // Hold the initial and final scenes so the transition can be read at a glance.
  double get _reveal {
    final time = loop?.value;
    if (time == null) return 1;
    if (time < 0.53) {
      return const Interval(
        0.22,
        0.42,
        curve: Curves.easeInOutCubic,
      ).transform(time);
    }
    return 1 -
        const Interval(
          0.67,
          0.87,
          curve: Curves.easeInOutCubic,
        ).transform(time);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 56) return;
    final accent = scheme.brightness == Brightness.dark
        ? const Color(0xFF72D3C9)
        : const Color(0xFF287E77);
    final muted = scheme.onSurfaceVariant.withValues(alpha: 0.28);
    final panel = scheme.surfaceContainerHighest;
    canvas.drawRect(Offset.zero & size, Paint()..color = scheme.surface);
    final stageWidth = size.width.clamp(0.0, 340.0);
    final left = (size.width - stageWidth) / 2 + 13;
    final width = (stageWidth - 56) / 2;
    final list = Rect.fromLTWH(left, 15, width, 74);
    final detail = list.shift(Offset(width + 30, 0));
    _rounded(canvas, list, panel, _windowRadius);
    _rounded(canvas, detail, panel, _windowRadius);
    _list(canvas, list, accent, muted, 1);

    final gap = Offset((list.right + detail.left) / 2, size.height / 2);
    final arrow = Path()
      ..moveTo(gap.dx - 2, gap.dy - 4)
      ..lineTo(gap.dx + 2, gap.dy)
      ..lineTo(gap.dx - 2, gap.dy + 4);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = scheme.onSurfaceVariant.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.5,
    );

    final reveal = _reveal;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(detail, const Radius.circular(_windowRadius)),
    );
    if (reveal < 1) {
      _list(
        canvas,
        detail.shift(Offset(-12 * reveal, 0)),
        accent,
        muted,
        1 - reveal,
      );
    }
    if (reveal > 0) {
      _detail(
        canvas,
        detail.shift(Offset(13 * (1 - reveal), 0)),
        accent,
        muted,
        reveal,
      );
    }
    canvas.restore();
  }

  void _list(
    Canvas canvas,
    Rect frame,
    Color accent,
    Color muted,
    double opacity,
  ) {
    _rounded(
      canvas,
      Rect.fromLTWH(frame.left + 9, frame.top + 10, frame.width * .37, 4),
      muted.withValues(alpha: muted.a * opacity),
      2,
    );
    for (var i = 0; i < 3; i++) {
      final y = frame.top + 20 + i * 15;
      final tone = i == 1
          ? accent.withValues(alpha: 0.22 * opacity)
          : scheme.surface.withValues(alpha: 0.66 * opacity);
      _rounded(
        canvas,
        Rect.fromLTWH(frame.left + 8, y, frame.width - 16, 12),
        tone,
        3,
      );
      _rounded(
        canvas,
        Rect.fromLTWH(frame.left + 11, y + 3, 7, 6),
        i == 1
            ? accent.withValues(alpha: 0.85 * opacity)
            : muted.withValues(alpha: muted.a * opacity),
        2,
      );
      _rounded(
        canvas,
        Rect.fromLTWH(frame.left + 22, y + 5, (frame.width - 27) * .62, 2.5),
        muted.withValues(alpha: muted.a * opacity),
        1.25,
      );
    }
  }

  void _detail(
    Canvas canvas,
    Rect frame,
    Color accent,
    Color muted,
    double opacity,
  ) {
    final cover = Rect.fromLTWH(
      frame.left + 9,
      frame.top + 12,
      frame.width * .30,
      49,
    );
    _rounded(canvas, cover, accent.withValues(alpha: 0.21 * opacity), 5);
    final glint = Path()
      ..moveTo(cover.left + cover.width * 0.14, cover.bottom - 7)
      ..lineTo(cover.center.dx, cover.top + 14)
      ..lineTo(cover.right - cover.width * 0.14, cover.bottom - 7)
      ..close();
    canvas.drawPath(
      glint,
      Paint()..color = accent.withValues(alpha: 0.55 * opacity),
    );
    final textLeft = cover.right + 8;
    final textWidth = (frame.right - textLeft - 8).clamp(0.0, frame.width);
    _rounded(
      canvas,
      Rect.fromLTWH(textLeft, frame.top + 20, textWidth, 5),
      accent.withValues(alpha: 0.81 * opacity),
      2,
    );
    _rounded(
      canvas,
      Rect.fromLTWH(textLeft, frame.top + 33, textWidth * .85, 3),
      muted.withValues(alpha: muted.a * opacity),
      1.5,
    );
    _rounded(
      canvas,
      Rect.fromLTWH(textLeft, frame.top + 43, textWidth * .62, 3),
      muted.withValues(alpha: muted.a * opacity),
      1.5,
    );
    _rounded(
      canvas,
      Rect.fromLTWH(textLeft, frame.top + 53, textWidth * .46, 3),
      muted.withValues(alpha: muted.a * opacity),
      1.5,
    );
  }

  void _rounded(Canvas canvas, Rect rect, Color color, double radius) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_MotionDiagram oldDelegate) =>
      scheme != oldDelegate.scheme || loop != oldDelegate.loop;
}
