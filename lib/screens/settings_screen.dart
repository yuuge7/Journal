import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:path/path.dart' as p;

import '../providers.dart';
import '../services/backup_service.dart';
import '../services/save_file.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _progress;

  Future<void> _export() async {
    final password = await _askPassword(confirm: true);
    if (password == null) return;
    final service = ref.read(backupServiceProvider);
    try {
      final file = await service.export(password,
          onProgress: (msg) => setState(() => _progress = msg));
      setState(() => _progress = null);
      await _deliverBackup(file.path);
    } catch (e) {
      setState(() => _progress = null);
      _snack('Export failed: $e');
    }
  }

  /// Lets the user choose where the finished backup goes.
  Future<void> _deliverBackup(String path) async {
    final fileName = p.basename(path);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
        ]),
      ),
    );
    switch (choice) {
      case 'save':
        final saved = await saveFileToDevice(path, fileName);
        _snack(saved ? 'Backup saved as $fileName' : 'Save cancelled');
      case 'share':
        await SharePlus.instance.share(ShareParams(
          files: [XFile(path)],
          subject: 'Journal backup',
        ));
    }
  }

  Future<void> _import() async {
    final picked = await openFile();
    final path = picked?.path;
    if (path == null) return;
    final password = await _askPassword(confirm: false);
    if (password == null) return;
    final service = ref.read(backupServiceProvider);
    try {
      final count = await service.import(File(path), password,
          onProgress: (msg) => setState(() => _progress = msg));
      setState(() => _progress = null);
      _snack('Imported $count entries');
    } on WrongPasswordException {
      setState(() => _progress = null);
      _snack('Wrong password or corrupted backup');
    } on FormatException catch (e) {
      setState(() => _progress = null);
      _snack(e.message);
    } catch (e) {
      setState(() => _progress = null);
      _snack('Import failed: $e');
    }
  }

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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const _SectionHeader('Backup'),
        ListTile(
          leading: const Icon(Icons.upload_outlined),
          title: const Text('Export encrypted backup'),
          subtitle: const Text(
              'ZIP with all entries + images, AES-256 encrypted with your password'),
          enabled: !busy,
          onTap: _export,
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Import backup'),
          subtitle: const Text('Merges a .mjbackup file into this device'),
          enabled: !busy,
          onTap: _import,
        ),
        if (busy)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 14),
              Expanded(child: Text(_progress!)),
            ]),
          ),
        const Divider(),
        const _SectionHeader('About'),
        const ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Your data stays on this device'),
          subtitle: Text(
              'Everything is stored locally in SQLite. Backups leave the device only when you share them.'),
        ),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
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
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _password,
          obscureText: _obscure,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Password',
            errorText: _error,
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
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
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
