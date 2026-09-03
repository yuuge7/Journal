import 'package:flutter/material.dart';

import 'palette.dart';

/// Names for the roles Material has no word for.
///
/// `ColorScheme` can say "primary" and "surfaceContainerHigh"; it cannot say
/// "the rule that runs down the feed" or "the only surface you are allowed to
/// write on". Those are the distinctions this app is actually made of, so they
/// get names here and the screens never reach for a raw colour.
@immutable
class JournalTokens extends ThemeExtension<JournalTokens> {
  const JournalTokens({
    required this.ground,
    required this.groundSunken,
    required this.page,
    required this.pageEdge,
    required this.hairline,
    required this.ink,
    required this.inkDim,
    required this.inkFaint,
    required this.accent,
    required this.accentSoft,
    required this.spine,
    required this.spineWeight,
    required this.danger,
  });

  /// The desk. Everything sits on it; it is never a card.
  final Color ground;

  /// One step below the ground, for rails and inset strips.
  final Color groundSunken;

  /// A sheet you can read or write an entry on. The *only* raised surface in
  /// the app — if something is a page, you can write on it.
  final Color page;

  /// The edge of a page, and the fill of controls that live on one.
  final Color pageEdge;

  /// 1px rules. Never a shadow, never an elevation tint.
  final Color hairline;

  /// Primary type, and the fill of the primary action.
  final Color ink;

  /// Secondary type: previews, subtitles, unselected controls.
  final Color inkDim;

  /// Utility type: counts, timestamps, labels. Still passes 4.5:1 on [ground].
  final Color inkFaint;

  /// Brass. Marks **today** and nothing else — today's node on the spine,
  /// today's cell in the calendar, the live streak, the entry being written
  /// right now. If it starts marking section headings or navigation it stops
  /// meaning anything, so it does not.
  final Color accent;

  /// Backing for the accent when it needs a field rather than a mark.
  final Color accentSoft;

  /// The rule running down the feed's gutter — the app's one signature shape.
  final Color spine;

  /// The weighted part of the spine: how long a day was spent writing.
  final Color spineWeight;

  /// Destructive actions only.
  final Color danger;

  static const light = JournalTokens(
    ground: Palette.deskGround,
    groundSunken: Palette.deskSunken,
    page: Palette.deskPage,
    pageEdge: Palette.deskPageEdge,
    hairline: Palette.deskHairline,
    ink: Palette.deskInk,
    inkDim: Palette.deskInkDim,
    inkFaint: Palette.deskInkFaint,
    accent: Palette.deskAccent,
    accentSoft: Palette.deskAccentSoft,
    spine: Palette.deskSpine,
    spineWeight: Palette.deskSpineWeight,
    danger: Palette.deskDanger,
  );

  static const dark = JournalTokens(
    ground: Palette.nightGround,
    groundSunken: Palette.nightSunken,
    page: Palette.nightPage,
    pageEdge: Palette.nightPageEdge,
    hairline: Palette.nightHairline,
    ink: Palette.nightInk,
    inkDim: Palette.nightInkDim,
    inkFaint: Palette.nightInkFaint,
    accent: Palette.nightAccent,
    accentSoft: Palette.nightAccentSoft,
    spine: Palette.nightSpine,
    spineWeight: Palette.nightSpineWeight,
    danger: Palette.nightDanger,
  );

  @override
  JournalTokens copyWith({
    Color? ground,
    Color? groundSunken,
    Color? page,
    Color? pageEdge,
    Color? hairline,
    Color? ink,
    Color? inkDim,
    Color? inkFaint,
    Color? accent,
    Color? accentSoft,
    Color? spine,
    Color? spineWeight,
    Color? danger,
  }) {
    return JournalTokens(
      ground: ground ?? this.ground,
      groundSunken: groundSunken ?? this.groundSunken,
      page: page ?? this.page,
      pageEdge: pageEdge ?? this.pageEdge,
      hairline: hairline ?? this.hairline,
      ink: ink ?? this.ink,
      inkDim: inkDim ?? this.inkDim,
      inkFaint: inkFaint ?? this.inkFaint,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      spine: spine ?? this.spine,
      spineWeight: spineWeight ?? this.spineWeight,
      danger: danger ?? this.danger,
    );
  }

  @override
  JournalTokens lerp(covariant JournalTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return JournalTokens(
      ground: c(ground, other.ground),
      groundSunken: c(groundSunken, other.groundSunken),
      page: c(page, other.page),
      pageEdge: c(pageEdge, other.pageEdge),
      hairline: c(hairline, other.hairline),
      ink: c(ink, other.ink),
      inkDim: c(inkDim, other.inkDim),
      inkFaint: c(inkFaint, other.inkFaint),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      spine: c(spine, other.spine),
      spineWeight: c(spineWeight, other.spineWeight),
      danger: c(danger, other.danger),
    );
  }
}

/// `context.tokens` reads better at the call site than a full
/// `Theme.of(context).extension<JournalTokens>()!` every time.
extension JournalTokensContext on BuildContext {
  JournalTokens get tokens => Theme.of(this).extension<JournalTokens>()!;
}
