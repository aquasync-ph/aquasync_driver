import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // 60% Dominant - Backgrounds
  static const Color dominantLightBlue = Color(0xFFF5FBFF); // Very Pale Blue / Frost White
  static const Color frostWhite = Color(0xFFFFFFFF);        // Solid White
  static const Color scaffold = dominantLightBlue;          // 60% Dominant Background
  static const Color surface = Colors.white;

  // 30% Secondary - Cards, Panels, & Sidebars
  static const Color darkRoyalBlue = Color(0xFF0F2573);     // Dark Royal Blue (Secondary Structure)
  static const Color border = Color(0xFFE2E8F0);            // Light Slate/Gray for borders
  static const Color secondary = darkRoyalBlue;
  static Color glassBackground = Colors.white.withValues(alpha: 0.75); // 75% Opacity White Glass
  static Color glassBorder = const Color(0xFFE2E8F0).withValues(alpha: 0.8);

  // 10% Accent - Buttons, Texts, & Highlights
  static const Color mediumBlue = Color(0xFF266CA9);        // Medium Blue (Accent)
  static const Color darkNavy = Color(0xFF041D56);          // Deep Sea Navy (Accent)
  static const Color midnightBlue = Color(0xFF01082D);      // Midnight Blue (Deepest Tone)
  static const Color accent = mediumBlue;

  // Typography Palette
  static const Color darkText = Color(0xFF0F2573);         // Dark Royal Blue acting as Secondary for Text
  static const Color slateText = Color(0xFF334155);        // Slate Gray Text
  static const Color grayText = Color(0xFF64748B);         // Subdued Gray Text

  // Functional Status Colors
  static const Color successGreen = Color(0xFF10B981);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color successBorder = Color(0xFF86EFAC);

  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color warningBorder = Color(0xFFFDE68A);

  static const Color errorRed = Color(0xFFEF4444);
  static const Color errorBg = Color(0xFFFEE2E2);
  static const Color errorBorder = Color(0xFFFCA5A5);

  // Legacy Aliases for seamless compatibility
  static const Color navy = darkNavy;
  static const Color primary = mediumBlue; // Mapped to 10% Accent
  static const Color tertiary = darkRoyalBlue; // Mapped to 30% Secondary
  static const Color primaryNavy = darkNavy;
  static const Color primaryBlue = mediumBlue;
  static const Color skyBlue = dominantLightBlue;
  static const Color background = scaffold;
  static const Color lightBg = Color(0xFFF1F5F9);
}

class AppGradients {
  // 60% Dominant Background Gradient (Pale Blue to White)
  static const LinearGradient frostBackground = LinearGradient(
    colors: [
      Color(0xFFF5FBFF),
      Colors.white,
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // 30% Secondary Panel Gradient (Dark Royal Blue)
  static const LinearGradient mediumBluePanel = LinearGradient(
    colors: [
      Color(0xFF0F2573),
      Color(0xFF0C1D5A),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // 10% Accent Button Gradient (Medium Blue to Deep Sea Navy)
  static const LinearGradient accentButton = LinearGradient(
    colors: [
      Color(0xFF266CA9),
      Color(0xFF041D56),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Deep Accent Gradient
  static const LinearGradient royalMidnight = LinearGradient(
    colors: [
      Color(0xFF266CA9),
      Color(0xFF01082D),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Aliases
  static const LinearGradient ocean = mediumBluePanel;
  static const LinearGradient electric = accentButton;
}

class AppDesign {
  static const double cardRadius = 24.0;
  static const double buttonRadius = 18.0;
  static const double inputRadius = 16.0;

  static List<BoxShadow> premiumShadow = [
    BoxShadow(
      color: AppColors.midnightBlue.withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 10),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: AppColors.mediumBlue.withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
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
    this.blur = 16.0,
    this.opacity = 0.75, // Defaulting to 75% for 30% Secondary Glass White
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
              color: borderColor ?? AppColors.border,
              width: 1.2,
            ),
            boxShadow: AppDesign.premiumShadow,
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
    this.height = 52,
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
                  HapticFeedback.lightImpact();
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
                  ? Colors.grey[300]
                  : (isCustomColor ? color : null),
              borderRadius: BorderRadius.circular(AppDesign.buttonRadius),
              border: isTranslucent
                  ? Border.all(
                      color: (textColor ?? color ?? AppColors.primary).withValues(alpha: 0.2),
                      width: 1.2,
                    )
                  : null,
              boxShadow: (onTap != null && !isTranslucent)
                  ? [
                      BoxShadow(
                        color: (color ?? AppColors.darkRoyalBlue)
                            .withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
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
                            color: effectiveTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
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
          seedColor: AppColors.darkRoyalBlue,
          primary: AppColors.darkRoyalBlue,
          secondary: AppColors.mediumBlue,
          tertiary: AppColors.darkNavy,
          surface: Colors.white,
          outline: AppColors.border,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.midnightBlue,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: AppColors.midnightBlue,
            letterSpacing: -0.3,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesign.cardRadius),
            side: const BorderSide(color: AppColors.border, width: 1.2),
          ),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.9),
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
                color: AppColors.darkRoyalBlue, width: 2),
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
            backgroundColor: AppColors.darkRoyalBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDesign.buttonRadius),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
            elevation: 4,
            shadowColor: AppColors.darkRoyalBlue.withValues(alpha: 0.35),
          ),
        ),
      );
}
