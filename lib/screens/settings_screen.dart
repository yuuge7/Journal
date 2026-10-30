import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../services/backup_service.dart';
import '../services/save_file.dart';
import '../services/platform_service.dart';
import '../services/readable_export_service.dart';
import 'bin_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _progress;
  double _fraction = 0;
  late final _version = PlatformService.call<String>('version');
  void _onProgress(BackupProgress progress) {
    if (mounted) {
      setState(() {
        _progress = progress.message;
        _fraction = progress.fraction.clamp(0, 1);
      });
    }
  }

  Future<void> _choice(
    String key,
    String title,
    Map<String, String> choices,
  ) async {
    final current = await ref.read(databaseProvider).setting(key);
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(title)),
            for (final item in choices.entries)
              ListTile(
                title: Text(item.value),
                trailing: current == item.key ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, item.key),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (key == 'backup_reminder') {
      try {
        await PlatformService.reminders(int.parse(choice));
      } catch (e) {
        _snack('Reminder could not be enabled: $e');
        return;
      }
    }
    await ref.read(databaseProvider).setSetting(key, choice);
  }

  Future<void> _readable(bool pdf) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Export readable ${pdf ? "PDF" : "Markdown"}?'),
        content: const Text(
          'This copy is readable without a password. Choose a private place to keep it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      setState(() {
        _progress = 'Preparing readable copy';
        _fraction = 0;
      });
      final service = ReadableExportService(
        ref.read(databaseProvider),
        ref.read(attachmentServiceProvider),
      );
      final file = pdf ? await service.pdf() : await service.markdown();
      if (!mounted) return;
      setState(() => _progress = null);
      await _deliverBackup(file.path, encrypted: false);
    } catch (e) {
      if (mounted) setState(() => _progress = null);
      _snack('Export failed: $e');
    }
  }

  Future<void> _export() async {
    final summary = await ref.read(backupServiceProvider).summary();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your backup contains'),
        content: Text(
          '${summary.entries} entries\n${summary.attachments} attachments\nAbout ${(summary.bytes / (1024 * 1024)).toStringAsFixed(1)} MB of attachments, plus your writing.\n\nEverything is encrypted before you choose where to save it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final password = await _askPassword(confirm: true);
    if (password == null) return;
    final service = ref.read(backupServiceProvider);
    try {
      final file = await service.export(password, onProgress: _onProgress);
      setState(() => _progress = null);
      await _deliverBackup(file.path);
    } catch (e) {
      if (mounted) setState(() => _progress = null);
      _snack('Export failed: $e');
    }
  }

  /// Lets the user choose where the finished backup goes.
  Future<void> _deliverBackup(String path, {bool encrypted = true}) async {
    final fileName = p.basename(path);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save to device'),
              subtitle: const Text('Pick a folder (Downloads by default)'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              subtitle: const Text('Send to another app or device'),
              onTap: () => Navigator.pop(context, 'share'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'save':
        final saved = await saveFileToDevice(path, fileName);
        if (saved && encrypted) {
          await ref
              .read(databaseProvider)
              .setSetting('last_backup', DateTime.now().toIso8601String());
          await PlatformService.call<void>('backupSaved');
        }
        _snack(saved ? 'Saved and verified as $fileName' : 'Save cancelled');
      case 'share':
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            subject: encrypted ? 'Journal backup' : 'My journal',
          ),
        );
        if (encrypted && result.status == ShareResultStatus.success) {
          await ref
              .read(databaseProvider)
              .setSetting('last_backup', DateTime.now().toIso8601String());
          await PlatformService.call<void>('backupSaved');
        }
    }
  }

  Future<void> _import() async {
    final policy = await showModalBottomSheet<DuplicatePolicy>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Restore from an encrypted Journal backup. How should entries already on this device be handled?',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: const Text('Keep existing entries'),
              subtitle: const Text(
                'Skip matching entries. Recommended for repeated imports.',
              ),
              onTap: () => Navigator.pop(context, DuplicatePolicy.skip),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Replace matching entries'),
              subtitle: const Text(
                'Use the copy in the backup for matching entry IDs.',
              ),
              onTap: () => Navigator.pop(context, DuplicatePolicy.replace),
            ),
          ],
        ),
      ),
    );
    if (policy == null) return;
    final path = await const MethodChannel(
      'journal/save_file',
    ).invokeMethod<String>('openFile');
    if (path == null) return;
    final password = await _askPassword(confirm: false);
    if (password == null) return;
    final service = ref.read(backupServiceProvider);
    try {
      final count = await service.import(
        File(path),
        password,
        duplicates: policy,
        onProgress: _onProgress,
      );
      setState(() => _progress = null);
      _snack('Imported $count entries');
    } on WrongPasswordException {
      setState(() => _progress = null);
      _snack('Wrong backup password');
    } on FormatException catch (e) {
      setState(() => _progress = null);
      _snack(e.message);
    } catch (e) {
      if (mounted) setState(() => _progress = null);
      _snack('Import failed: $e');
    }
  }

  Future<void> _pickDayEndsAt(int current) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Your day ends at',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var hour = 0; hour <= AppDatabase.maxDayEndsAt; hour++)
                    ListTile(
                      title: Text(_hourLabel(hour)),
                      selected: hour == current,
                      trailing: hour == current
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, hour),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await ref.read(databaseProvider).setDayEndsAt(picked);
  }

  static String _hourLabel(int hour) => hour == 0
      ? 'Midnight'
      : DateFormat.Hm().format(DateTime(2000, 1, 1, hour));

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _askPassword({required bool confirm}) {
    return showDialog<String>(
      context: context,
      builder: (context) => _PasswordDialog(confirm: confirm),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _progress != null;
    final dayEndsAt = ref.watch(dayEndsAtProvider).value ?? 0;
    final theme = ref.watch(preferenceProvider('theme')).value ?? 'system';
    final lock = ref.watch(preferenceProvider('app_lock')).value == 'true';
    final secure =
        ref.watch(preferenceProvider('secure_screen')).value == 'true';
    final reminder =
        ref.watch(preferenceProvider('backup_reminder')).value ?? '0';
    final lastBackup = ref.watch(preferenceProvider('last_backup')).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: Theme.of(context).textTheme.displayLarge,
        ),
        toolbarHeight: 72,
      ),
      body: ListView(
        children: [
          const _SectionHeader('Appearance and privacy'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: Text(
              theme == 'system'
                  ? 'Follow system'
                  : theme == 'dark'
                  ? 'Dark'
                  : 'Light',
            ),
            onTap: () => _choice('theme', 'Theme', {
              'system': 'Follow system',
              'light': 'Light',
              'dark': 'Dark',
            }),
          ),
          SwitchListTile(
            title: const Text('App lock'),
            subtitle: const Text(
              'Unlock with your device biometrics or PIN. Locks when Journal goes into the background.',
            ),
            value: lock,
            onChanged: (value) async {
              try {
                if (await PlatformService.authenticate()) {
                  await ref
                      .read(databaseProvider)
                      .setSetting('app_lock', '$value');
                }
              } catch (e) {
                _snack(e.toString());
              }
            },
          ),
          SwitchListTile(
            title: const Text('Hide screenshots and recents'),
            subtitle: const Text(
              'Prevent screenshots and hide writing in the app switcher.',
            ),
            value: secure,
            onChanged: (value) => ref
                .read(databaseProvider)
                .setSetting('secure_screen', '$value'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Recently deleted'),
            subtitle: const Text('Restore entries and notebooks for 30 days'),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const BinScreen())),
          ),
          const _SectionHeader('Writing'),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Start new entries blank'),
            subtitle: const Text(
              'Clear the remembered template. You can choose another from the editor.',
            ),
            onTap: () async {
              await ref
                  .read(databaseProvider)
                  .setSetting('default_template', '[{"insert":"\\n"}]');
              _snack('New entries will start blank');
            },
          ),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Day ends at'),
            subtitle: Text(
              dayEndsAt == 0
                  ? 'An entry for yesterday written after midnight is marked '
                        '"written a day later". Pick a later hour if you write at night.'
                  : 'An entry for yesterday written before '
                        '${_hourLabel(dayEndsAt)} is not marked "written a day later".',
            ),
            trailing: Text(_hourLabel(dayEndsAt)),
            onTap: () => _pickDayEndsAt(dayEndsAt),
          ),
          const Divider(),
          const _SectionHeader('Backup'),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Backup reminders'),
            subtitle: Text(
              reminder == '0'
                  ? 'Off \u00b7 local reminders only'
                  : 'Every $reminder days since your last saved backup',
            ),
            onTap: () => _choice('backup_reminder', 'Remind me to back up', {
              '0': 'Off',
              '7': 'Every 7 days',
              '14': 'Every 14 days',
              '30': 'Every 30 days',
            }),
          ),
          ListTile(
            title: const Text('Last saved backup'),
            subtitle: Text(
              lastBackup == null
                  ? 'No backup saved yet'
                  : DateFormat.yMMMd().add_Hm().format(
                      DateTime.parse(lastBackup),
                    ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Export readable Markdown'),
            subtitle: const Text('Writing plus attachments in an open format'),
            enabled: !busy,
            onTap: () => _readable(false),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Export readable PDF'),
            subtitle: const Text('A printable copy of your writing and photos'),
            enabled: !busy,
            onTap: () => _readable(true),
          ),
          ListTile(
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Export a backup'),
            subtitle: const Text(
              'One encrypted file holding every entry, photo and tag. '
              'You choose the password, and only that password opens it.',
            ),
            enabled: !busy,
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Import a backup'),
            subtitle: const Text(
              'Choose whether to skip or replace entries already on this device.',
            ),
            enabled: !busy,
            onTap: _import,
          ),
          if (busy)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: LinearProgressIndicator(value: _fraction),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(_progress!)),
                ],
              ),
            ),
          const Divider(),
          const _SectionHeader('About'),
          FutureBuilder<String?>(
            future: _version,
            builder: (context, snapshot) => ListTile(
              title: const Text('Journal'),
              subtitle: Text('Version ${snapshot.data ?? "..."}'),
              trailing: TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://github.com/yuuge7/Journal/releases'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Release notes'),
              ),
            ),
          ),
          const ListTile(
            title: Text('What Journal never does'),
            subtitle: Text(
              'No network permission. No analytics. No account. No automatic cloud backup. Photos, voice and optional location stay here. Nothing leaves unless you export it.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Your writing stays on this device'),
            subtitle: Text(
              'There is no account and nothing is uploaded. A backup is the '
              'only copy that ever leaves the phone, and only when you send it.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.utility,
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.confirm});

  /// true = export flow (asks twice), false = import flow (asks once).
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _password.text;
    if (p.length < 4) {
      setState(() => _error = 'At least 4 characters');
      return;
    }
    if (widget.confirm && p != _repeat.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirm ? 'Set backup password' : 'Backup password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Password',
                errorText: _error,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (widget.confirm) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _repeat,
                obscureText: _obscure,
                decoration: const InputDecoration(labelText: 'Repeat password'),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
