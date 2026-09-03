import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'palette.dart';
import 'tokens.dart';

/// Two faces, three registers.
///
/// * **Schibsted Grotesk** carries the app talking to you — dates, labels,
///   buttons, counts. A humanist grotesque with a high x-height, so it stays
///   legible at 11sp where the meta lines live.
/// * **Literata** carries *your* prose, and only your prose: the preview on a
///   feed row and the body of the editor. Journalling apps reflexively put a
///   serif in the chrome and leave the writing in the system sans; this does
///   the opposite, because the reading face earns its keep on the long text,
///   not on a screen title.
/// * The **utility register** is Schibsted Grotesk at 11sp, uppercase, widely
///   tracked, with tabular figures. It is a treatment rather than a third
///   family — one more font would be costume, not information.
class AppType {
  const AppType._();

  static const display = 'Schibsted Grotesk';
  static const reading = 'Literata';

  /// Digits that do not jitter when a count ticks over. Every number the app
  /// shows goes through a style carrying this.
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];

  static TextTheme scale(Color ink, Color inkDim, Color inkFaint) {
    return TextTheme(
      // The date at the top of the feed. The largest thing on any screen.
      displayLarge: TextStyle(
        fontFamily: display,
        fontSize: 30,
        height: 1.12,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: ink,
        fontFeatures: tabular,
      ),
      // Screen titles that are not the feed.
      displayMedium: TextStyle(
        fontFamily: display,
        fontSize: 23,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: ink,
        fontFeatures: tabular,
      ),
      // Big numerals in statistics.
      displaySmall: TextStyle(
        fontFamily: display,
        fontSize: 26,
        height: 1.1,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: ink,
        fontFeatures: tabular,
      ),
      titleLarge: TextStyle(
        fontFamily: display,
        fontSize: 19,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: ink,
      ),
      // An entry's title on a feed row.
      titleMedium: TextStyle(
        fontFamily: display,
        fontSize: 16.5,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontFamily: display,
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      // Your writing, in the editor.
      bodyLarge: TextStyle(
        fontFamily: reading,
        fontSize: 16,
        height: 1.62,
        color: ink,
      ),
      // Your writing, previewed on a feed row.
      bodyMedium: TextStyle(
        fontFamily: reading,
        fontSize: 14.5,
        height: 1.5,
        color: inkDim,
      ),
      // The app's own sentences: subtitles, explanations, empty states.
      bodySmall: TextStyle(
        fontFamily: display,
        fontSize: 13.5,
        height: 1.45,
        color: inkDim,
      ),
      labelLarge: TextStyle(
        fontFamily: display,
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: ink,
      ),
      labelMedium: TextStyle(
        fontFamily: display,
        fontSize: 11.5,
        height: 1.2,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: inkDim,
        fontFeatures: tabular,
      ),
      // The utility register.
      labelSmall: TextStyle(
        fontFamily: display,
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.85,
        color: inkFaint,
        fontFeatures: tabular,
      ),
    );
  }
}

/// Reaches the registers that have no slot in [TextTheme].
extension AppTextStyles on TextTheme {
  /// 11sp, tracked, tabular. Pair with `.toUpperCase()` on the string — the
  /// tracking is set for caps.
  TextStyle get utility => labelSmall!;

  /// Counts and durations sitting inline with body copy.
  TextStyle get meta => labelMedium!;
}

/// Radii. Four steps, all small: the app should read as sheets of paper with
/// cut edges, not as the stack of 12/16/28dp lozenges Material hands out.
class Radii {
  const Radii._();
  static const chip = BorderRadius.all(Radius.circular(4));
  static const card = BorderRadius.all(Radius.circular(8));
  static const sheet = BorderRadius.vertical(top: Radius.circular(14));
  static const dialog = BorderRadius.all(Radius.circular(14));
}

/// Motion budget for the whole app: three durations, no more.
class Motion {
  const Motion._();

  /// State feedback — the "saved" stamp, a chip filling in.
  static const quick = Duration(milliseconds: 130);

  /// Moving between screens.
  static const page = Duration(milliseconds: 190);

  /// Something appearing that the reader has to notice.
  static const reveal = Duration(milliseconds: 260);
}

ThemeData buildTheme({required Brightness brightness}) {
  final t = brightness == Brightness.light ? JournalTokens.light : JournalTokens.dark;
  final text = AppType.scale(t.ink, t.inkDim, t.inkFaint);
  final onAccent = brightness == Brightness.light ? Palette.deskPage : Palette.nightGround;

  // Written out rather than seeded. Material widgets still read these, but no
  // screen picks a colour from here — screens use JournalTokens.
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.ink,
    onPrimary: t.ground,
    primaryContainer: t.pageEdge,
    onPrimaryContainer: t.ink,
    secondary: t.inkDim,
    onSecondary: t.ground,
    secondaryContainer: t.pageEdge,
    onSecondaryContainer: t.ink,
    tertiary: t.accent,
    onTertiary: onAccent,
    tertiaryContainer: t.accentSoft,
    onTertiaryContainer: t.ink,
    error: t.danger,
    onError: onAccent,
    errorContainer: t.accentSoft,
    onErrorContainer: t.danger,
    surface: t.page,
    onSurface: t.ink,
    onSurfaceVariant: t.inkDim,
    surfaceContainerLowest: t.groundSunken,
    surfaceContainerLow: t.ground,
    surfaceContainer: t.page,
    surfaceContainerHigh: t.pageEdge,
    surfaceContainerHighest: t.pageEdge,
    outline: t.hairline,
    outlineVariant: t.hairline,
    shadow: const Color(0x00000000),
    scrim: const Color(0x99000000),
    inverseSurface: t.ink,
    onInverseSurface: t.ground,
    inversePrimary: t.ground,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [t],
    scaffoldBackgroundColor: t.ground,
    canvasColor: t.ground,
    textTheme: text,
    fontFamily: AppType.display,
    // Material 3's default ink is InkSparkle, which is instantly recognisable
    // as "a Flutter app". A plain ripple reads as the app's own.
    splashFactory: InkRipple.splashFactory,
    // ...and the default page transition is the M3 zoom. Fade-forwards is
    // quieter and does not make every push feel like a system animation.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: t.ground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 20,
      titleTextStyle: text.displayMedium,
      iconTheme: IconThemeData(color: t.ink, size: 22),
      actionsIconTheme: IconThemeData(color: t.inkDim, size: 22),
      systemOverlayStyle: brightness == Brightness.light
          ? SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: t.ground,
              systemNavigationBarIconBrightness: Brightness.dark)
          : SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: t.ground,
              systemNavigationBarIconBrightness: Brightness.light),
    ),
    dividerTheme: DividerThemeData(color: t.hairline, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: t.inkDim, size: 22),
    cardTheme: CardThemeData(
      color: t.page,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: t.hairline),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.inkDim,
      textColor: t.ink,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      minVerticalPadding: 10,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: t.ink,
      surfaceTintColor: Colors.transparent,
      side: BorderSide(color: t.hairline),
      shape: const RoundedRectangleBorder(borderRadius: Radii.chip),
      labelStyle: text.labelLarge!.copyWith(fontSize: 13),
      secondaryLabelStyle: text.labelLarge!.copyWith(fontSize: 13, color: t.ground),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      showCheckmark: false,
      elevation: 0,
      pressElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.ink,
        foregroundColor: t.ground,
        disabledBackgroundColor: t.hairline,
        disabledForegroundColor: t.inkFaint,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
        textStyle: text.labelLarge,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: BorderSide(color: t.hairline),
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: t.inkDim,
        minimumSize: const Size(48, 48),
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      hintStyle: text.bodySmall!.copyWith(color: t.inkFaint),
      labelStyle: text.bodySmall,
      floatingLabelStyle: text.utility.copyWith(color: t.inkDim),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.hairline)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.ink, width: 2)),
      errorBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.danger)),
      focusedErrorBorder:
          UnderlineInputBorder(borderSide: BorderSide(color: t.danger, width: 2)),
      errorStyle: text.bodySmall!.copyWith(color: t.danger),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.ink,
      selectionColor: t.accentSoft,
      selectionHandleColor: t.inkDim,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.page,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.dialog,
        side: BorderSide(color: t.hairline),
      ),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodySmall,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.page,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: t.hairline,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.ink,
      contentTextStyle: text.bodySmall!.copyWith(color: t.ground),
      actionTextColor: t.accent,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: Radii.card),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.ink,
      linearTrackColor: t.hairline,
      circularTrackColor: t.hairline,
      strokeWidth: 2,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.ink, borderRadius: Radii.chip),
      textStyle: text.bodySmall!.copyWith(color: t.ground),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: t.page,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      headerBackgroundColor: t.page,
      headerForegroundColor: t.ink,
      todayForegroundColor: WidgetStatePropertyAll(t.accent),
      todayBorder: BorderSide(color: t.accent),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.dialog,
        side: BorderSide(color: t.hairline),
      ),
    ),
  );
}
