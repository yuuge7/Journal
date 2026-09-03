import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/nav_bar.dart';
import 'calendar_screen.dart';
import 'feed_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  static const _screens = [
    FeedScreen(),
    CalendarScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  // Named the way the person thinks about them, not after the screen classes.
  static const _items = [
    NavItem(
        icon: Icons.notes_outlined,
        activeIcon: Icons.notes_rounded,
        label: 'Entries'),
    NavItem(
        icon: Icons.calendar_today_outlined,
        activeIcon: Icons.calendar_today_rounded,
        label: 'Calendar'),
    NavItem(
        icon: Icons.show_chart_outlined,
        activeIcon: Icons.show_chart_rounded,
        label: 'Progress'),
    NavItem(
        icon: Icons.tune_outlined,
        activeIcon: Icons.tune_rounded,
        label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: AppNavBar(
        items: _items,
        index: _tab,
        onSelected: (i) => setState(() => _tab = i),
      ),
    );
  }
}
