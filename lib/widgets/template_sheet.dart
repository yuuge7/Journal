import 'package:flutter/material.dart';

import '../data/templates.dart';

/// Bottom sheet with the pre-defined writing templates.
Future<WritingTemplate?> showTemplateSheet(BuildContext context) {
  return showModalBottomSheet<WritingTemplate>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Start with a template',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final t in writingTemplates)
                  ListTile(
                    leading: Text(t.emoji, style: const TextStyle(fontSize: 24)),
                    title: Text(t.name),
                    subtitle: Text(t.description),
                    onTap: () => Navigator.pop(context, t),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
