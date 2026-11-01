import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../domain/appearance.dart';
import 'app_theme.dart';

/// Liquid Glass surfaces for AsterLink.
///
/// These widgets extend the existing appearance system instead of replacing it.
/// Every value is derived from [AppAppearance], so the palette, glass style,
/// blur sigma and opacity the user already configured in 设置 → 外观 keep
/// working. What this file adds is the *rendering* language of Liquid Glass:
///
/// * continuous curvature (squircle) instead of a plain circular arc
/// * a refraction gradient: bright top rim + soft bottom bounce
/// * a specular hairline border that makes the edge catch the light
/// * a two-layer shadow (tight ambient + far direct)
///
/// Nothing here is selectable on its own. Surfaces follow the current
/// [GlassStyle], and [GlassStyle.clear] reads closest to Liquid Glass.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    this.child,
    this.radius = 22,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.opacity,
    this.blurSigma,
    this.shadow = true,
    this.refraction = true,
    this.onTap,
    this.semanticLabel,
  });

  final Widget? child;

  /// Continuous corner radius.
  final double radius;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  /// Overrides the resolved glass opacity, clamped to 0..1.
  final double? opacity;

  /// Overrides the resolved blur sigma, clamped to 0..64.
  final double? blurSigma;

  /// Whether to paint the two-layer shadow. Disable it inside long lists.
  final bool shadow;

  /// Whether to paint the refraction gradient.
  final bool refraction;

  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Continuous-curvature shape, used so glass and ink agree on the outline.
  static OutlinedBorder shape(
    double radius, {
    BorderSide side = BorderSide.none,
  }) =>
      RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(radius),
        side: side,
      );

  @override
  Widget build(BuildContext context) {
    final appearance = AppAppearance.of(context);
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;

    final glassOpacity = (opacity ?? appearance.glassOpacity).clamp(0.0, 1.0);
    final sigma = (blurSigma ?? appearance.blurSigma).clamp(0.0, 64.0);

    final borderRadius = BorderRadius.circular(radius);
    final bool blur = sigma > 0;

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: appearance.glassColor.withValues(alpha: glassOpacity),
        gradient: refraction ? _refraction(appearance, dark) : null,
        border: Border.all(
          color: _rimColor(appearance, dark),
          width: 1,
        ),
      ),
      child: child,
    );

    if (blur) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        // Isolate the glass from backdrop repaints.
        child: RepaintBoundary(child: surface),
      );
    }

    surface = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: surface,
    );

    if (onTap != null) {
      surface = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: surface,
      );
    }

    if (semanticLabel != null) {
      surface = Semantics(
        label: semanticLabel,
        container: true,
        child: surface,
      );
    }

    Widget result = surface;

    if (shadow) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: _shadows(dark, glassOpacity),
        ),
        child: result,
      );
    }

    if (padding != null || margin != null || width != null || height != null) {
      result = Container(
        width: width,
        height: height,
        margin: margin,
        padding: padding,
        child: result,
      );
    }

    return result;
  }

  /// Top rim highlight → transparent middle → bottom bounce.
  ///
  /// The middle stop carries a trace of [AppAppearance.lensColor] so the glass
  /// picks up a hint of the accent instead of reading as flat grey.
  LinearGradient _refraction(AppAppearance appearance, bool dark) {
    final top = dark ? 0.16 : 0.42;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Colors.white.withValues(alpha: top),
        Colors.white.withValues(alpha: top * 0.28),
        appearance.lensColor.withValues(alpha: dark ? 0.10 : 0.06),
        Colors.transparent,
        Colors.white.withValues(alpha: top * 0.18),
        Colors.white.withValues(alpha: top * 0.42),
      ],
      stops: const <double>[0.0, 0.12, 0.32, 0.60, 0.86, 1.0],
    );
  }

  /// Specular hairline. Darker glass needs a brighter rim to stay readable.
  Color _rimColor(AppAppearance appearance, bool dark) => dark
      ? Colors.white.withValues(alpha: 0.22)
      : Colors.white.withValues(alpha: 0.70);

  List<BoxShadow> _shadows(bool dark, double glassOpacity) {
    final strength = dark ? 0.34 : 0.18;
    // Opaque surfaces already separate from the background; keep them flat.
    final scale = glassOpacity >= 0.99 ? 0.35 : 1.0;
    final ambient = strength * 0.45 * scale;
    final direct = strength * scale;
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: ambient),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: direct),
        blurRadius: 22,
        offset: const Offset(0, 8),
        spreadRadius: -4,
      ),
    ];
  }
}

/// A glass card with sensible defaults for content blocks.
class LiquidGlassCard extends StatelessWidget {
  const LiquidGlassCard({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.opacity,
    this.onTap,
    this.shadow = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? opacity;
  final VoidCallback? onTap;
  final bool shadow;

  @override
  Widget build(BuildContext context) => LiquidGlass(
        radius: radius,
        padding: padding,
        margin: margin,
        opacity: opacity,
        onTap: onTap,
        shadow: shadow,
        child: child,
      );
}

/// A capsule glass button with a press-scale bounce.
class LiquidGlassButton extends StatefulWidget {
  const LiquidGlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = 50,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.expanded = false,
    this.enabled = true,
    this.semanticLabel,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double height;
  final EdgeInsetsGeometry padding;
  final bool expanded;
  final bool enabled;
  final String? semanticLabel;

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onPressed != null;
    final foreground = enabled
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).disabledColor;

    Widget button = AnimatedScale(
      scale: _pressed ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: const Cubic(0.34, 1.56, 0.64, 1.0),
      child: LiquidGlass(
        radius: widget.height / 2,
        height: widget.height,
        padding: widget.padding,
        onTap: enabled ? widget.onPressed : null,
        semanticLabel: widget.semanticLabel,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
          child: Center(child: widget.child),
        ),
      ),
    );

    if (widget.expanded) {
      button = SizedBox(width: double.infinity, child: button);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        behavior: HitTestBehavior.translucent,
        child: button,
      ),
    );
  }
}

/// A hairline separator tuned for use between glass rows.
class LiquidGlassDivider extends StatelessWidget {
  const LiquidGlassDivider({
    super.key,
    this.height = 1,
    this.indent = 16,
  });

  final double height;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent),
      child: Container(
        height: height,
        color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.12),
      ),
    );
  }
}

/// Whether the current style renders as glass at all.
///
/// Callers can use this to skip glass entirely on low-end devices or when the
/// user picked [GlassStyle.solid], falling back to a plain filled surface.
bool usesLiquidGlass(BuildContext context) =>
    AppAppearance.of(context).glassStyle != GlassStyle.solid;
