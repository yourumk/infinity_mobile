import 'dart:ui';
import 'package:flutter/material.dart';

/// iOS 26–style Glassmorphism Card.
/// Translucent background + blur + ultra-thin borders.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final bool isDark;
  final Border? border;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.padding,
    this.color,
    this.isDark = true,
    this.border,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    // ── Light Mode — iOS 26 frosted white ──
    if (!isDark) {
      return ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: padding ?? const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color ?? Colors.white.withOpacity(0.72),
              borderRadius: radius,
              border: border ?? Border.all(
                color: borderColor ?? Colors.white.withOpacity(0.85),
                width: borderColor != null ? 1.5 : 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 24,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 60,
                  spreadRadius: -8,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: child,
          ),
        ),
      );
    }

    // ── Dark Mode — iOS 26 dark glass ──
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: (color ?? const Color(0xFF2A2A3C)).withOpacity(0.45),
            borderRadius: radius,
            border: border ?? Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.10),
              width: borderColor != null ? 1.5 : 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 30,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}