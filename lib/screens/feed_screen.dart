import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/entry_row.dart';
import '../widgets/formatting.dart';
import '../widgets/nav_bar.dart';
import '../widgets/time_spine.dart';
import 'editor_screen.dart';
import 'journals_screen.dart';

/// The feed.
///
/// Everything else in the app is a way back into this list, so this is the
/// surface that got rebuilt rather than re-skinned. Three things changed:
///
/// 1. Entries are grouped by the day they belong to and hung off a single
///    [SpineRail], instead of each carrying its own repeated date on its own
///    card. The day is stated once; the rows underneath only carry what differs.
/// 2. The spine is weighted by minutes written and broken by days missed, so
///    scrolling shows the shape of a month rather than a uniform stack.
/// 3. The header is the date and the state of today — not the app's own name,
///    which the person opening the app already knows.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    setState(() => _searching = false);
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).set('');
  }

  void _write({DateTime? date}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(
        journalId: ref.read(selectedJournalProvider),
        initialDate: date,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final feed = ref.watch(feedProvider);
    final journals = ref.watch(journalsProvider).value ?? const <Journal>[];
    final selected = ref.watch(selectedJournalProvider);
    final query = ref.watch(searchQueryProvider);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: feed.when(
          loading: () => const _FeedLoading(),
          error: (e, st) {
            debugPrint('feed failed: $e\n$st');
            return _FeedError(onRetry: () => ref.invalidate(feedProvider));
          },
          data: (entries) => CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _TopBar(
                  height: 56 * scale.clamp(1.0, 1.5),
                  ground: t.ground,
                  searching: _searching,
                  controller: _searchController,
                  // Not "All journals": the rail directly underneath already
                  // says that, and a pinned bar repeating the control below it
                  // is wasted. This says how much there is to read instead.
                  filterLabel: [
                    if (selected != null)
                      journals
                              .where((j) => j.id == selected)
                              .firstOrNull
                              ?.name
                              .toUpperCase() ??
                          '',
                    formatCount(entries.length, 'entry', 'entries')
                        .toUpperCase(),
                  ].where((s) => s.isNotEmpty).join('  ·  '),
                  onQuery: (q) => ref.read(searchQueryProvider.notifier).set(q),
                  onOpenSearch: () => setState(() => _searching = true),
                  onCloseSearch: _closeSearch,
                  onOpenJournals: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const JournalsScreen())),
                ),
              ),
              if (!_searching) const SliverToBoxAdapter(child: _FeedHeader()),
              if (journals.length > 1)
                SliverToBoxAdapter(
                  child: _JournalRail(
                    journals: journals,
                    selected: selected,
                    onSelect: (id) =>
                        ref.read(selectedJournalProvider.notifier).select(id),
                  ),
                ),
              if (!_searching) const SliverToBoxAdapter(child: _ThrowbackBand()),
              ..._buildDays(entries, selected, journals.length),
              if (entries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _FeedEmpty(
                    query: query,
                    journalName: selected == null
                        ? null
                        : journals.where((j) => j.id == selected).firstOrNull?.name,
                    onClearSearch: _closeSearch,
                    onShowAll: () =>
                        ref.read(selectedJournalProvider.notifier).select(null),
                    onWrite: _write,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 108)),
            ],
          ),
        ),
          ),
          // The writing runs under the Write button, so the last 96dp fade to
          // the ground. Without it the button sits on top of a half-covered
          // line of someone's prose, which is the one thing a reading surface
          // must not do.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 96,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [t.ground.withValues(alpha: 0), t.ground],
                    stops: const [0, 0.62],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: WriteButton(onPressed: _write),
    );
  }

  /// Flattens the feed into day headings, entry rows and the gaps between them.
  ///
  /// The provider already hands back entries newest-first, so a single pass
  /// keeps the day keys in order; the gap between two consecutive keys is
  /// measured with [dayOrdinal] rather than `Duration.inDays`, which reports a
  /// DST-shortened day as no day at all.
  List<Widget> _buildDays(List<Entry> entries, int? selected, int journalCount) {
    if (entries.isEmpty) return const [];
    final groups = <DateTime, List<Entry>>{};
    for (final e in entries) {
      groups.putIfAbsent(localDay(e.entryDate), () => []).add(e);
    }
    final days = groups.keys.toList();
    final today = dayOrdinal(DateTime.now());
    final showJournal = selected == null && journalCount > 1;

    final children = <Widget>[];
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final dayEntries = groups[day]!;
      final seconds =
          dayEntries.fold<int>(0, (sum, e) => sum + e.writingSeconds);
      // 45 minutes fills the segment. An hour left every ordinary day
      // drawing the same hairline, which defeats the point of weighting it.
      final weight = (seconds / 2700).clamp(0.0, 1.0);
      final isToday = dayOrdinal(day) == today;

      children.add(SliverToBoxAdapter(
        child: _DayHeading(
          day: day,
          seconds: seconds,
          count: dayEntries.length,
          isToday: isToday,
          isFirst: i == 0,
        ),
      ));
      children.add(SliverList.builder(
        itemCount: dayEntries.length,
        itemBuilder: (context, j) => SpineRail(
          weight: weight,
          capBottom: i == days.length - 1 && j == dayEntries.length - 1,
          child: EntryRow(
            entry: dayEntries[j],
            showJournal: showJournal,
          ),
        ),
      ));

      if (i < days.length - 1) {
        final missing = dayOrdinal(day) - dayOrdinal(days[i + 1]) - 1;
        if (missing > 0) {
          children.add(SliverToBoxAdapter(child: _Gap(days: missing)));
        }
      }
    }
    return children;
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// Pinned strip: what you are looking at, and the two ways to change it.
class _TopBar extends SliverPersistentHeaderDelegate {
  _TopBar({
    required this.height,
    required this.ground,
    required this.searching,
    required this.controller,
    required this.filterLabel,
    required this.onQuery,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onOpenJournals,
  });

  final double height;
  final Color ground;
  final bool searching;
  final TextEditingController controller;
  final String filterLabel;
  final ValueChanged<String> onQuery;
  final VoidCallback onOpenSearch, onCloseSearch, onOpenJournals;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final text = Theme.of(context).textTheme;
    return Container(
      height: height,
      color: ground,
      padding: const EdgeInsets.only(left: 20, right: 8),
      child: Row(
        children: [
          Expanded(
            child: searching
                ? TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    style: text.titleSmall,
                    decoration: const InputDecoration(
                      hintText: 'Search titles and writing',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: onQuery,
                  )
                : Text(filterLabel.toUpperCase(),
                    style: text.utility, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: searching ? 'Close search' : 'Search entries',
            icon: Icon(searching ? Icons.close : Icons.search, size: 21),
            onPressed: searching ? onCloseSearch : onOpenSearch,
          ),
          if (!searching)
            IconButton(
              tooltip: 'Manage journals',
              icon: const Icon(Icons.collections_bookmark_outlined, size: 20),
              onPressed: onOpenJournals,
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TopBar old) =>
      old.height != height ||
      old.ground != ground ||
      old.searching != searching ||
      old.filterLabel != filterLabel;
}

/// Today's date and where you stand — the only place the accent is spent on
/// this screen besides today's bead on the spine.
class _FeedHeader extends ConsumerWidget {
  const _FeedHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final streak = ref.watch(streaksProvider).value;
    final entries = ref.watch(feedProvider).value ?? const <Entry>[];
    final wroteToday = entries.any((e) =>
        !e.isDraft && dayOrdinal(e.entryDate) == dayOrdinal(now));

    final facts = <String>[
      if (streak != null && streak.current > 0)
        '${streak.current}-day streak'
      else
        'no streak right now',
      wroteToday ? 'written today' : 'nothing yet today',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('EEEE').format(now).toUpperCase(), style: text.utility),
          const SizedBox(height: 3),
          Text(DateFormat('d MMMM').format(now), style: text.displayLarge),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Today's bead, matching the one on the spine: a ring while the
              // day is still empty, filled once something is written.
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: wroteToday ? t.accent : Colors.transparent,
                    border: Border.all(color: t.accent, width: 1.5),
                  ),
                ),
              ),
              Expanded(
                child: Text(facts.join('  ·  '),
                    style: text.meta.copyWith(color: t.inkDim)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Which notebook the feed is showing. Pills, not `FilterChip`s: the stock chip
/// is a 32dp lozenge with a checkmark that slides in, and four of them in a row
/// is the single most recognisable Material component on a screen.
class _JournalRail extends StatelessWidget {
  const _JournalRail({
    required this.journals,
    required this.selected,
    required this.onSelect,
  });

  final List<Journal> journals;
  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _Pill(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final j in journals)
            _Pill(
              label: j.name,
              color: Color(j.color),
              selected: selected == j.id,
              onTap: () => onSelect(selected == j.id ? null : j.id),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.chip,
        // The visible pill is 32dp; the tap target around it is the full 48.
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Center(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              // Selected is a page-white chip with an ink edge, not a solid
              // ink slab. Filling it made the filter the heaviest object on
              // the screen, and navigation is never allowed to outweigh the
              // writing or the one primary action.
              decoration: BoxDecoration(
                color: selected ? t.page : Colors.transparent,
                borderRadius: Radii.chip,
                border: Border.all(
                  color: selected ? t.ink : t.hairline,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (color != null) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.all(Radius.circular(1.5)),
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Text(
                    label,
                    style: text.labelLarge!.copyWith(
                      fontSize: 13,
                      color: selected ? t.ink : t.inkDim,
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

// ---------------------------------------------------------------------------
// Day structure
// ---------------------------------------------------------------------------

/// The date, said once, with the day's total time beside it.
class _DayHeading extends StatelessWidget {
  const _DayHeading({
    required this.day,
    required this.seconds,
    required this.count,
    required this.isToday,
    required this.isFirst,
  });

  final DateTime day;
  final int seconds;
  final int count;
  final bool isToday;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final thisYear = day.year == DateTime.now().year;
    final label = isToday
        ? 'Today'
        : DateFormat(thisYear ? 'EEE d MMM' : 'EEE d MMM yyyy').format(day);
    final time = formatWritingTime(seconds);

    return SpineRail(
      node: isToday ? SpineNode.today : SpineNode.day,
      weight: (seconds / 3600).clamp(0.0, 1.0),
      capTop: isFirst,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 20, 6),
        child: Wrap(
          spacing: 10,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label.toUpperCase(),
              style: text.utility.copyWith(
                color: isToday ? t.accent : t.inkDim,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (time.isNotEmpty)
              Text(time.toUpperCase(), style: text.utility),
            if (count > 1)
              Text(formatCount(count, 'entry', 'entries').toUpperCase(),
                  style: text.utility),
          ],
        ),
      ),
    );
  }
}

/// A run of days with nothing in it. Drawn, rather than closed up, because a
/// journal that hides its gaps cannot show a streak honestly.
class _Gap extends StatelessWidget {
  const _Gap({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SpineRail(
      dotted: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 11, 20, 11),
        child: Text(
          formatGap(days).toUpperCase(),
          style: Theme.of(context).textTheme.utility.copyWith(color: t.inkFaint),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// On this day
// ---------------------------------------------------------------------------

/// Entries from the same date in earlier years.
///
/// Previously a filled card containing more cards. It is now a band between two
/// rules: the same information, one level of nesting fewer, and it can sit
/// above the spine without competing with it.
class _ThrowbackBand extends ConsumerWidget {
  const _ThrowbackBand();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final entries = ref.watch(throwbackProvider).value ?? const <Entry>[];
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.hairline),
          bottom: BorderSide(color: t.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 9, 20, 1),
            child: Text('ON THIS DAY', style: text.utility),
          ),
          for (final e in entries.take(3)) _ThrowbackRow(entry: e),
          if (entries.length > 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
              child: Text(
                '${entries.length - 3} more from this date'.toUpperCase(),
                style: text.utility,
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// One line per memory. Deliberately set in the display face rather than the
/// reading face: this band is an index into older entries, not a place to read
/// them, and setting it as prose made it outrank today's writing underneath.
class _ThrowbackRow extends StatelessWidget {
  const _ThrowbackRow({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final years = DateTime.now().year - entry.entryDate.year;
    final title = entry.title.trim().isNotEmpty
        ? entry.title.trim()
        : entry.plainText.replaceAll(RegExp(r'\s+'), ' ').trim();

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EditorScreen(entryId: entry.id))),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        child: Row(
          children: [
            // Widens with the text scale rather than staying at 62dp, where
            // "1 year" wrapped onto two lines at the largest system font.
            SizedBox(
              width: 62 *
                  (MediaQuery.textScalerOf(context).scale(11) / 11)
                      .clamp(1.0, 2.0),
              child: Text(
                years == 1 ? '1 year' : '$years years',
                style: text.meta.copyWith(color: t.inkFaint),
              ),
            ),
            Expanded(
              child: Text(
                title.isEmpty ? 'Empty entry' : title,
                style: text.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

class _FeedLoading extends StatelessWidget {
  const _FeedLoading();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator()),
          const SizedBox(height: 14),
          Text('OPENING YOUR JOURNAL', style: text.utility),
        ],
      ),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Couldn't read your entries", style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Nothing has been lost — every entry is still in the database '
                'on this device. Try again, and if it keeps failing, close the '
                'app and reopen it.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty({
    required this.query,
    required this.journalName,
    required this.onClearSearch,
    required this.onShowAll,
    required this.onWrite,
  });

  final String query;
  final String? journalName;
  final VoidCallback onClearSearch;
  final VoidCallback onShowAll;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final searching = query.trim().isNotEmpty;

    final (String title, String body, String action, VoidCallback onAction) =
        switch ((searching, journalName)) {
      (true, _) => (
          'No entry matches "${query.trim()}"',
          'Search looks at titles and the writing itself. A shorter word usually finds more.',
          'Clear search',
          onClearSearch,
        ),
      (false, final String name) => (
          'Nothing in $name yet',
          'This journal is empty. Write the first entry in it, or go back to all journals.',
          'Show all journals',
          onShowAll,
        ),
      _ => (
          'Nothing written yet',
          'A first entry does not have to be long. One line about today is a start, '
              'and it stays on this device.',
          'Write today',
          onWrite,
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleLarge),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(body, style: text.bodySmall),
          ),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}
