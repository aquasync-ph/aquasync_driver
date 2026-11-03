import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // iOS 18 / Apple Pro Titanium & Deep Navy Design System
  static const Color iosBackground = Color(0xFFF2F4F8);      // Ultra-clean iOS system background
  static const Color dominantLightBlue = Color(0xFFF5FBFF); // Frost White / Pale Blue
  static const Color frostWhite = Color(0xFFFFFFFF);        // Pure White
  static const Color scaffold = iosBackground;              
  static const Color surface = Colors.white;

  // iOS Secondary & Structured Surfaces
  static const Color darkRoyalBlue = Color(0xFF0F2573);     // Deep Royal Blue
  static const Color appleBlue = Color(0xFF007AFF);         // Native iOS System Blue
  static const Color border = Color(0xFFE2E8F0);            // Sleek Light Border
  static const Color iosCardBorder = Color(0xFFD1D5DB);     // Refined iOS Border
  static const Color secondary = darkRoyalBlue;
  
  static Color glassBackground = Colors.white.withValues(alpha: 0.82); // Frosted Glass Opacity
  static Color glassBorder = const Color(0xFFFFFFFF).withValues(alpha: 0.9);

  // High-Tech Accent Palette
  static const Color mediumBlue = Color(0xFF266CA9);        // Premium Accent Blue
  static const Color darkNavy = Color(0xFF041D56);          // High-Tech Navy
  static const Color midnightBlue = Color(0xFF01082D);      // Midnight Space Blue
  static const Color accent = appleBlue;

  // Typography Palette (SF Pro / Modern iOS Style)
  static const Color darkText = Color(0xFF0B192C);         // Deep Tech Dark
  static const Color slateText = Color(0xFF334155);        // Slate Text
  static const Color grayText = Color(0xFF64748B);         // Subdued Gray

  // Functional Status Colors (Apple HIG Aligned)
  static const Color successGreen = Color(0xFF34C759);      // iOS System Green
  static const Color successBg = Color(0xFFE8F8EC);
  static const Color successBorder = Color(0xFF86EFAC);

  static const Color warningAmber = Color(0xFFFF9500);      // iOS System Orange/Amber
  static const Color warningBg = Color(0xFFFFF7ED);
  static const Color warningBorder = Color(0xFFFDE68A);

  static const Color errorRed = Color(0xFFFF3B30);          // iOS System Red
  static const Color errorBg = Color(0xFFFEE2E2);
  static const Color errorBorder = Color(0xFFFCA5A5);

  // Legacy Aliases
  static const Color navy = darkNavy;
  static const Color primary = appleBlue;
  static const Color tertiary = darkRoyalBlue;
  static const Color primaryNavy = darkNavy;
  static const Color primaryBlue = mediumBlue;
  static const Color skyBlue = dominantLightBlue;
  static const Color background = scaffold;
  static const Color lightBg = Color(0xFFF8FAFC);
}

class AppGradients {
  // iOS Ultra-Clean Background Gradient
  static const LinearGradient frostBackground = LinearGradient(
    colors: [
      Color(0xFFF8FAFC),
      Color(0xFFEEF2F6),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // High-Tech iOS Dark Titanium Panel
  static const LinearGradient iosDarkPanel = LinearGradient(
    colors: [
      Color(0xFF0F2573),
      Color(0xFF041D56),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Vibrant Apple Blue Gradient
  static const LinearGradient accentButton = LinearGradient(
    colors: [
      Color(0xFF007AFF),
      Color(0xFF0056B3),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Royal Midnight High-Tech Glow
  static const LinearGradient royalMidnight = LinearGradient(
    colors: [
      Color(0xFF266CA9),
      Color(0xFF01082D),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient ocean = iosDarkPanel;
  static const LinearGradient electric = accentButton;

  // Medium Blue Panel Gradient
  static const LinearGradient mediumBluePanel = LinearGradient(
    colors: [
      Color(0xFF266CA9),
      Color(0xFF0F2573),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppDesign {
  // iOS 18 Style Radii (Smooth Rounded Corners)
  static const double cardRadius = 22.0;
  static const double buttonRadius = 16.0;
  static const double inputRadius = 14.0;
  static const double badgeRadius = 10.0;

  // iPhone-grade Multi-layered Soft Shadows (HIG Depth)
  static List<BoxShadow> iosCardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 20,
      offset: const Offset(0, 8),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: AppColors.appleBlue.withValues(alpha: 0.06),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> premiumShadow = iosCardShadow;
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final double opacity;
  final double borderRadius;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.blur = 20.0,
    this.opacity = 0.85,
    this.borderRadius = AppDesign.cardRadius,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.8),
              width: 1.2,
            ),
            boxShadow: AppDesign.iosCardShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class LiquidButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final IconData? icon;
  final Color? color;
  final Color? textColor;
  final double height;

  const LiquidButton({
    super.key,
    required this.label,
    this.onTap,
    this.isLoading = false,
    this.icon,
    this.color,
    this.textColor,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final isCustomColor = color != null;
    final isTranslucent = isCustomColor && (color!.opacity < 0.9);

    final effectiveTextColor = textColor ??
        (isTranslucent ? AppColors.darkRoyalBlue : Colors.white);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap != null
              ? () {
                  HapticFeedback.mediumImpact(); // iOS Tactile Feedback
                  onTap!();
                }
              : null,
          borderRadius: BorderRadius.circular(AppDesign.buttonRadius),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              gradient: onTap != null && !isCustomColor
                  ? AppGradients.accentButton
                  : null,
              color: onTap == null
                  ? Colors.grey[200]
                  : (isCustomColor ? color : null),
              borderRadius: BorderRadius.circular(AppDesign.buttonRadius),
              boxShadow: (onTap != null && !isTranslucent)
                  ? [
                      BoxShadow(
                        color: (color ?? AppColors.appleBlue)
                            .withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      )
                    ]
                  : null,
            ),
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: effectiveTextColor,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(
                            icon,
                            color: effectiveTextColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: effectiveTextColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class AquaTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        fontFamily: 'Poppins',
        scaffoldBackgroundColor: AppColors.scaffold,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.appleBlue,
          primary: AppColors.appleBlue,
          secondary: AppColors.darkRoyalBlue,
          tertiary: AppColors.mediumBlue,
          surface: Colors.white,
          outline: AppColors.border,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.darkText,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.darkText,
            letterSpacing: -0.4,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesign.cardRadius),
            side: const BorderSide(color: AppColors.border, width: 1.0),
          ),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesign.inputRadius),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesign.inputRadius),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesign.inputRadius),
            borderSide: const BorderSide(
                color: AppColors.appleBlue, width: 2),
          ),
          labelStyle: const TextStyle(
              color: AppColors.grayText,
              fontSize: 14,
              fontWeight: FontWeight.w600),
          hintStyle:
              const TextStyle(color: AppColors.grayText, fontSize: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.appleBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDesign.buttonRadius),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
            elevation: 4,
            shadowColor: AppColors.appleBlue.withValues(alpha: 0.35),
          ),
        ),
      );
}
