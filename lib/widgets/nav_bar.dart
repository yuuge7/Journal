import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class NavItem {
  const NavItem({required this.icon, required this.activeIcon, required this.label});
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The bottom bar, rebuilt.
///
/// Material's `NavigationBar` is one of the most recognisable "this was not
/// designed" tells in an Android app: a 80dp bar with a coloured pill sliding
/// behind the selected icon, tinted with the theme's primary. That made
/// navigation the brightest thing on every screen. Here the bar is the same
/// ground as the page, the only mark of selection is ink weight plus the top
/// rule thickening under the active tab, and no accent is spent on it at all.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelected,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;

    return Container(
      color: t.ground,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    label: items[i].label,
                    excludeSemantics: true,
                    child: InkResponse(
                      onTap: () => onSelected(i),
                      radius: 44,
                      containedInkWell: true,
                      highlightShape: BoxShape.rectangle,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: Container(
                              height: i == index ? 2 : 1,
                              color: i == index ? t.ink : t.hairline,
                            ),
                          ),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  i == index ? items[i].activeIcon : items[i].icon,
                                  size: 21,
                                  color: i == index ? t.ink : t.inkFaint,
                                ),
                                const SizedBox(height: 4),
                                // The horizontal padding is what lets a long
                                // label ellipsize instead of running into its
                                // neighbour at large text scales.
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                  items[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.labelMedium!.copyWith(
                                    color: i == index ? t.ink : t.inkFaint,
                                    fontWeight:
                                        i == index ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one action the whole app exists for.
///
/// A rectangle with the word on it, not a circular FAB with a pencil glyph: at
/// 48dp tall it is a bigger target than the FAB it replaces, it says what it
/// does, and it is filled with ink rather than the accent — the accent means
/// "today" everywhere else and spending it here would make it mean nothing.
class WriteButton extends StatelessWidget {
  const WriteButton({super.key, required this.onPressed, this.label = 'Write'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.ink,
      borderRadius: Radii.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        // No `alignment:` on this container — that would make it expand to the
        // full width the Scaffold offers the floating slot.
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_outlined, size: 18, color: t.ground),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge!.copyWith(color: t.ground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
