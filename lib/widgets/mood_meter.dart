import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// How a day felt, 1–5, as five equal segments filled from the left.
///
/// This replaces the row of 😞😕😐🙂😄. Emoji were doing two jobs at once —
/// they were the only mood control *and* the only colour on the card — and they
/// render differently on every Android skin, which is the fastest way to make a
/// designed screen look assembled.
///
/// The segments are all the same height on purpose. A first pass drew them as
/// rising bars and, sat next to "48 words · 14 min", it read as a signal-
/// strength icon rather than a scale. Equal segments read as steps on a track,
/// and they spend no colour: the accent stays reserved for today.
const moodLabels = ['Rough', 'Low', 'Even', 'Good', 'Great'];

String moodLabel(int mood) => moodLabels[mood.clamp(1, 5) - 1];

class MoodMeter extends StatelessWidget {
  const MoodMeter({super.key, required this.mood, this.size = 11, this.color});

  /// 1–5.
  final int mood;

  /// Height of the tallest bar.
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filled = color ?? t.inkDim;
    final value = mood.clamp(1, 5);
    // Grows with the text around it, but not all the way: at a 2x system font
    // the gauge would otherwise stay the size it is at 1x and read as a speck
    // beside 26sp type.
    final scale =
        (MediaQuery.textScalerOf(context).scale(11) / 11).clamp(1.0, 1.6);
    final size = this.size * scale;
    return Semantics(
      label: 'Mood: ${moodLabel(value)}, $value of 5',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 1; i <= 5; i++) ...[
            if (i > 1) SizedBox(width: size * 0.18),
            Container(
              width: size * 0.42,
              height: size * 0.27,
              decoration: BoxDecoration(
                color: i <= value ? filled : t.hairline,
                borderRadius: BorderRadius.all(Radius.circular(size * 0.1)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The editor's mood control: five 48dp targets, each a meter over its word.
class MoodPicker extends StatelessWidget {
  const MoodPicker({super.key, required this.mood, required this.onChanged});

  final int? mood;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: true,
            selected: mood == i,
            label: moodLabels[i - 1],
            excludeSemantics: true,
            child: InkWell(
              borderRadius: const BorderRadius.all(Radius.circular(6)),
              // Tapping the value that is already set clears it: a day without
              // a mood is a normal thing to record.
              onTap: () => onChanged(mood == i ? null : i),
              child: Container(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    MoodMeter(
                      mood: i,
                      size: 14,
                      color: mood == i ? t.ink : t.inkFaint,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      moodLabels[i - 1],
                      style: text.labelSmall!.copyWith(
                        color: mood == i ? t.ink : t.inkFaint,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
