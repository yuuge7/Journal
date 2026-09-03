import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Width of the gutter every feed item reserves on its left.
const double kSpineWidth = 32;
const double _spineX = 13;

/// What, if anything, sits on the spine at this row.
enum SpineNode {
  /// No bead — an entry hanging off the day above it.
  none,

  /// A day that has entries.
  day,

  /// Today. The only place the accent appears in the feed.
  today,
}

/// The rule that runs down the left of the feed, and the one shape this app is
/// meant to be remembered by.
///
/// It is drawn from the two things this journal knows that a cloud diary does
/// not: which day an entry *belongs to* (`entryDate`, not `createdAt`), and how
/// many minutes were actually spent at the page (`writingSeconds`). A day you
/// sat with for an hour draws a thick, dark segment; a day you dashed off a
/// line draws a hairline; days you missed draw as a dotted gap with the span
/// spelled out. Scrolling the feed therefore shows the *shape* of a month —
/// which is exactly what a streak-keeping journal should show and what a stack
/// of identical cards cannot.
class SpineRail extends StatelessWidget {
  const SpineRail({
    super.key,
    required this.child,
    this.node = SpineNode.none,
    this.weight = 0,
    this.dotted = false,
    this.capTop = false,
    this.capBottom = false,
  });

  final Widget child;
  final SpineNode node;

  /// 0–1: share of an hour spent writing on this day. Sets the segment's
  /// thickness and darkness.
  final double weight;

  /// Draw the segment as a dashed line — a run of days with no entries.
  final bool dotted;

  /// Stop the line short at the very start or the very end of the feed, so it
  /// does not look severed by the edge of the screen.
  final bool capTop;
  final bool capBottom;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // A Stack, not a Row: these rails are laid out inside slivers, where the
    // height is unbounded. A Row with `CrossAxisAlignment.stretch` would ask
    // the gutter to be infinitely tall, and an IntrinsicHeight would make every
    // row in the feed measure twice. The Stack takes its height from the
    // content and the painter fills whatever that turns out to be.
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: kSpineWidth,
          child: CustomPaint(
            painter: _SpinePainter(
              line: t.spine,
              weightColor: t.spineWeight,
              accent: t.accent,
              ground: t.ground,
              node: node,
              weight: weight.clamp(0, 1),
              dotted: dotted,
              capTop: capTop,
              capBottom: capBottom,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: kSpineWidth),
          child: child,
        ),
      ],
    );
  }
}

class _SpinePainter extends CustomPainter {
  _SpinePainter({
    required this.line,
    required this.weightColor,
    required this.accent,
    required this.ground,
    required this.node,
    required this.weight,
    required this.dotted,
    required this.capTop,
    required this.capBottom,
  });

  final Color line, weightColor, accent, ground;
  final SpineNode node;
  final double weight;
  final bool dotted, capTop, capBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final top = capTop ? size.height * 0.5 : 0.0;
    final bottom = capBottom ? size.height * 0.5 : size.height;
    if (bottom <= top) return;

    if (dotted) {
      final paint = Paint()
        ..color = line
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;
      for (var y = top; y < bottom; y += 6) {
        canvas.drawLine(Offset(_spineX, y), Offset(_spineX, math.min(y + 2, bottom)), paint);
      }
    } else {
      canvas.drawLine(
        Offset(_spineX, top),
        Offset(_spineX, bottom),
        Paint()
          ..color = Color.lerp(line, weightColor, 0.18 + 0.82 * weight)!
          ..strokeWidth = 1 + 3.2 * weight,
      );
    }

    if (node == SpineNode.none) return;
    final isToday = node == SpineNode.today;
    final centre = Offset(_spineX, size.height / 2);
    // Punch the line out behind the bead so it reads as a bead on a thread
    // rather than a dot painted over a rule.
    canvas.drawCircle(centre, 6.5, Paint()..color = ground);
    canvas.drawCircle(centre, 4, Paint()..color = isToday ? accent : weightColor);
    if (isToday) {
      canvas.drawCircle(
        centre,
        7,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_SpinePainter old) =>
      old.line != line ||
      old.weightColor != weightColor ||
      old.accent != accent ||
      old.ground != ground ||
      old.node != node ||
      old.weight != weight ||
      old.dotted != dotted ||
      old.capTop != capTop ||
      old.capBottom != capBottom;
}
