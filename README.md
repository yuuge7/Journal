# Journal

A modern, offline-first journaling app for Android built with Flutter. All data stays on the device in a local SQLite database; the only way anything leaves is a password-encrypted backup you export yourself.

## Features

**Writing**
- Rich text editor (flutter_quill) with headers, lists, checkboxes, bold/italic/underline, code and color
- Background auto-save: every edit is debounced (rxdart, 2 s quiet period) and persisted as a draft — closing the app never loses text
- Pre-defined writing templates (Daily Reflection, Gratitude, Dream Log, Travel Log, Goals Check-in) offered in a bottom sheet on every new entry
- Image attachments from camera or gallery, with thumbnail strip and full-screen viewer
- Mood picker (1–5) per entry
- Entry date can differ from creation date — backfill old memories onto the day they happened

**Organization**
- Chronological feed (`ListView.builder`) with full-text search over titles and content
- Multiple journals/categories (1-to-N) with custom name, color and emoji; filter the feed per journal
- Tag system (M-to-N via a junction table) with inline tag creation

**Reliving memories**
- "On this day" throwback: SQL `strftime('%m-%d', …)` day+month match surfaces entries from previous years at the top of the feed
- Calendar view (table_calendar) with dot markers on days that have entries; tap a day to list them or write for that date

**Statistics**
- Word count per entry (live while typing) and time spent writing per entry (accumulating stopwatch)
- Writing streaks: current and longest run of consecutive days, computed from distinct entry days
- Totals: entries, words, writing time, photos, average words per entry, plus a 30-day activity chart

**Backup**
- Export: everything (entries, journals, tags, images) packed into a ZIP, encrypted with a password of your choice, then saved anywhere on the device via the system file picker (Downloads by default) or shared to another app
- Import: merges a backup into the current device — journals and tags matched by name, entries always added

## Backup format

A `.mjbackup` file is a chunked AES-256-GCM container around a ZIP:

```
magic "MJRNLv1\0" (8 B) | salt (16 B) | PBKDF2 iterations (4 B BE)
then per chunk: cipherLen (4 B BE) | nonce (12 B) | ciphertext | GCM tag (16 B)
```

- Key: PBKDF2-HMAC-SHA256, 210 000 iterations, 256-bit
- Plaintext chunks of 1 MiB, so encryption and decryption run with bounded memory regardless of archive size
- Inside the ZIP: `manifest.json`, `journals.json`, `tags.json`, `entries.ndjson`, `images/…`
- Entries are NDJSON (one JSON object per line): export streams them out of the database in pages, import parses them line by line — no full-dataset materialization on either side

A wrong password fails GCM authentication on the first chunk and is reported cleanly.

## Architecture

| Layer | Choice |
|---|---|
| Database | drift (SQLite) with reactive `watch()` queries |
| State | flutter_riverpod (`StreamProvider`s over drift streams) |
| Editor | flutter_quill 11 |
| Debounce | rxdart `debounceTime` |
| Calendar | table_calendar |
| Backup crypto | cryptography (PBKDF2 + AES-GCM), archive (ZIP) |

```
lib/
├── main.dart                  # app + theme (Material 3, light/dark)
├── providers.dart             # all Riverpod providers
├── data/
│   ├── database.dart          # drift tables + queries (throwback, calendar, streaks, stats)
│   └── templates.dart         # writing templates as quill deltas
├── services/
│   ├── attachment_service.dart# image storage in app documents dir
│   ├── backup_service.dart    # encrypted export/import
│   └── save_file.dart         # bridge to the SAF save channel
├── screens/                   # feed, editor, calendar, stats, journals, settings, home shell
└── widgets/                   # entry card, template sheet
```

Schema: `journals 1—N entries`, `entries M—N tags` (via `entry_tags`), `entries 1—N attachments`. Attachment rows store file names only; the bytes live in `attachments/` under the app documents directory. Foreign keys cascade, so deleting a journal or entry cleans up everything beneath it.

The "save to device" flow is a small platform channel (`journal/save_file`) in `MainActivity.kt` that fires an `ACTION_CREATE_DOCUMENT` intent and streams the file to whatever location the user picks — no storage permissions needed.

## Building

```bash
flutter pub get
dart run build_runner build          # drift codegen (after schema changes)
flutter build apk                    # or: flutter run
```

Regenerate launcher icons after changing `assets/icon/*.png`:

```bash
dart run flutter_launcher_icons
```

### Known constraints

- `intl` is pinned to `^0.20.2` (flutter_localizations pins it); loosening it makes the resolver pick a years-old flutter_quill
- `file_picker` is deliberately not used: its bundled Kotlin Gradle Plugin does not compile under Flutter 3.44's built-in Kotlin. File opening uses the first-party `file_selector`; saving uses the custom platform channel above
- Android only (`flutter create --platforms android`); no iOS/desktop targets configured
