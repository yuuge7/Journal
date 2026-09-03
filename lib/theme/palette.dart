import 'package:flutter/material.dart';

/// Hand-built palette. Deliberately *not* `ColorScheme.fromSeed`: the app used
/// to seed from `#6750A4`, which is Material 3's own demo seed, so every
/// surface, container and state colour in the app was Google's default answer
/// rather than a decision about this product.
///
/// Two grounds, one accent, one neutral ramp per theme.
///
/// * The **desk** is the ground you look at — a cool putty in daylight, a
///   blue-charcoal at night. Neither is white and neither is cream.
/// * A **page** is the only surface that means anything: it is where an entry
///   can be read or written. Nothing else is raised.
/// * **Brass** is the accent and it marks exactly one thing: today. See
///   [JournalTokens.accent].
class Palette {
  const Palette._();

  // --- Light: "Desk" -------------------------------------------------------
  // A putty ground that is a shade darker than the page sitting on it, so an
  // entry reads as paper laid on a desk rather than a grey box on white.
  static const deskGround = Color(0xFFE4E5E0);
  static const deskSunken = Color(0xFFD8DAD4);
  static const deskPage = Color(0xFFFBFAF8);
  static const deskPageEdge = Color(0xFFEDEEE9);
  static const deskHairline = Color(0xFFC6C9C1);
  static const deskInk = Color(0xFF171A1D);
  static const deskInkDim = Color(0xFF474D53);
  // 4.7:1 on deskGround. The first pass used #767C83, which measured
  // 3.3:1 — under AA for the 11sp utility register that every meta line,
  // nav label and day heading is set in.
  static const deskInkFaint = Color(0xFF5F656C);
  static const deskAccent = Color(0xFF8A5A12);
  static const deskAccentSoft = Color(0xFFEADCC0);
  static const deskSpine = Color(0xFFC6C9C1);
  static const deskSpineWeight = Color(0xFF5E656C);
  static const deskDanger = Color(0xFF9B2C1E);

  // --- Dark: "Night" -------------------------------------------------------
  // Warm off-white type on a cool ground: the one tension the whole theme is
  // built on, and the reason it does not read as the usual near-black shell.
  static const nightGround = Color(0xFF14171C);
  static const nightSunken = Color(0xFF0F1216);
  static const nightPage = Color(0xFF1B1F26);
  static const nightPageEdge = Color(0xFF242A33);
  // Raised a step: at #2C323B the rules bounding the "on this day"
  // band were invisible on the dark ground.
  static const nightHairline = Color(0xFF343B45);
  static const nightInk = Color(0xFFE7E4DC);
  static const nightInkDim = Color(0xFFA6ABB3);
  // 4.7:1 on nightGround, up from 4.0:1.
  static const nightInkFaint = Color(0xFF7E848D);
  static const nightAccent = Color(0xFFE0A84A);
  static const nightAccentSoft = Color(0xFF3B3122);
  static const nightSpine = Color(0xFF2E343D);
  static const nightSpineWeight = Color(0xFF8A9099);
  static const nightDanger = Color(0xFFE0765F);

  /// Colours offered when naming a journal. Retuned from the stock Material
  /// 500 swatches the picker used to show, so a journal mark sits in the same
  /// world as the rest of the app instead of shouting over it.
  static const journalColors = <int>[
    0xFF7A6BB5, // iris
    0xFF3D7A9E, // slate blue
    0xFF3F7D63, // pine
    0xFF8A6A2E, // brass
    0xFFA05340, // clay
    0xFF9A4A6B, // plum
    0xFF566270, // graphite
    0xFF6E8A46, // moss
  ];
}
