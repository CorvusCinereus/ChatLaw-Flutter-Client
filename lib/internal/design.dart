/**
 * @file design.dart
 * @brief 全局设计基准（颜色 / 间距 / 圆角 / 字体层级 / 主题）
 * @author CorvusCinereus
 *
 * 说明：全应用此前没有主题与设计变量（单一 TextStyle 管所有文字、间距与
 * 圆角取值混杂）。此文件集中定义一套 token，并由 AppConfig（用户字号/颜色/
 * 字体族）派生出 ThemeData，供 MaterialApp 使用；页面只允许引用这里的常量，
 * 不再写魔法数字。
 */

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'config.dart';

/// 颜色
class AppColors {
  static const brand = Color(0xFF2B6BFF);
  static const brandDark = Color(0xFF1E4FD0);
  static const brandSoft = Color(0xFFEAF1FF);

  static const bg = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFF1F2329);
  static const textSecondary = Color(0xFF646A73);
  static const textTertiary = Color(0xFF8F959E);

  static const border = Color(0xFFE5E6EB);
  static const divider = Color(0xFFEFF0F3);

  static const danger = Color(0xFFE5484D);

  /// 聊天气泡
  static const userBubble = brand;
  static const userBubbleText = Color(0xFFFFFFFF);
  static const assistantBubble = Color(0xFFFFFFFF);
}

/// 间距（只允许这套取值）
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// 页面水平内边距
  static const page = 16.0;
  static const pageWide = 24.0;
}

/// 圆角
class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

/// 动画时长
class AppDuration {
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 250);
}

/// 响应式断点
class AppBreakpoints {
  static const compact = 600.0;
  static const medium = 900.0;
}

/// 关键尺寸
class AppSizes {
  static const contentMaxWidth = 840.0;
  static const formMaxWidth = 560.0;
  static const bubbleMaxWidth = 560.0;
  static const dialogMaxWidth = 420.0;
  static const sheetMaxWidth = 640.0;
  static const touchTarget = 48.0;
  static const appBarHeight = 56.0;
}

/// 主题构建
class AppTheme {
  /// 页面水平内边距：宽屏更宽松。
  static double pagePadding(double width) =>
      width >= AppBreakpoints.medium ? AppSpacing.pageWide : AppSpacing.page;

  /// 由用户配置派生主题；配置未就绪时使用默认基准。
  static ThemeData build(AppConfig? config) {
    final base = config?.textStyle;
    final fontSize =
        base?.fontSize ?? (Platform.isAndroid ? 15.0 : 16.0);
    final textColor = base?.color ?? AppColors.textPrimary;
    final family = base?.fontFamily;

    TextStyle t(
      double size, {
      FontWeight weight = FontWeight.w400,
      Color? color,
      double? height,
    }) =>
        TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color ?? textColor,
          fontFamily: family,
          height: height,
        );

    final textTheme = TextTheme(
      titleLarge: t(fontSize + 6, weight: FontWeight.w600, color: AppColors.textPrimary),
      titleMedium: t(fontSize + 3, weight: FontWeight.w600, color: AppColors.textPrimary),
      titleSmall: t(fontSize + 1, weight: FontWeight.w600, color: AppColors.textPrimary),
      bodyLarge: t(fontSize, height: 1.4),
      bodyMedium: t(fontSize, height: 1.4),
      bodySmall: t(fontSize - 1, color: AppColors.textSecondary, height: 1.35),
      labelLarge: t(fontSize, weight: FontWeight.w500),
      labelMedium: t(fontSize - 1, color: AppColors.textSecondary),
    );

    final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand).copyWith(
      surface: AppColors.surface,
      error: AppColors.danger,
    );

    final controlRadius = BorderRadius.circular(AppRadius.md);
    final cardRadius = BorderRadius.circular(AppRadius.lg);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: family,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarThemeData(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: AppSizes.appBarHeight,
        titleSpacing: AppSpacing.page,
        titleTextStyle:
            t(fontSize + 3, weight: FontWeight.w600, color: AppColors.textPrimary),
        shape: const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: cardRadius,
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme:
          const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: const Size(0, AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: t(fontSize, weight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: t(fontSize, weight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(0, AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: controlRadius),
          textStyle: t(fontSize, weight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.bg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: t(fontSize, color: AppColors.textTertiary),
        labelStyle: t(fontSize - 1, color: AppColors.textSecondary),
        floatingLabelStyle: t(fontSize - 1, color: AppColors.brand),
        errorStyle: t(fontSize - 2, color: AppColors.danger),
        errorMaxLines: 2,
        border: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: const BorderSide(color: AppColors.brand, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: controlRadius,
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        constraints: const BoxConstraints(maxWidth: AppSizes.dialogMaxWidth),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle:
            t(fontSize + 3, weight: FontWeight.w600, color: AppColors.textPrimary),
        contentTextStyle: t(fontSize, color: AppColors.textPrimary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        titleTextStyle: t(fontSize, color: AppColors.textPrimary),
        subtitleTextStyle: t(fontSize - 1, color: AppColors.textSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: t(fontSize, color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brand,
        linearMinHeight: 6,
      ),
    );
  }
}
