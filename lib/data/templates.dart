import 'dart:convert';

/// A pre-defined writing template. [deltaJson] is a Quill delta document.
class WritingTemplate {
  final String name;
  final String description;
  final String emoji;
  final String deltaJson;

  const WritingTemplate({
    required this.name,
    required this.description,
    required this.emoji,
    required this.deltaJson,
  });
}

String _delta(List<Map<String, dynamic>> ops) => jsonEncode(ops);

final List<WritingTemplate> writingTemplates = [
  WritingTemplate(
    name: 'Blank',
    description: 'Start from scratch',
    emoji: '📝',
    deltaJson: _delta([
      {'insert': '\n'}
    ]),
  ),
  WritingTemplate(
    name: 'Daily Reflection',
    description: 'Review your day with guided prompts',
    emoji: '🌅',
    deltaJson: _delta([
      {'insert': 'How was my day?'},
      {
        'insert': '\n',
        'attributes': {'header': 2}
      },
      {'insert': '\n\nWhat went well?'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n\nWhat could have gone better?'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n\nOne thing I learned today'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n'},
    ]),
  ),
  WritingTemplate(
    name: 'Gratitude',
    description: 'Three things you are grateful for',
    emoji: '🙏',
    deltaJson: _delta([
      {'insert': 'Today I am grateful for…'},
      {
        'insert': '\n',
        'attributes': {'header': 2}
      },
      {'insert': ''},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'}
      },
      {'insert': ''},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'}
      },
      {'insert': ''},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'}
      },
      {'insert': '\nWhy these matter to me'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n'},
    ]),
  ),
  WritingTemplate(
    name: 'Dream Log',
    description: 'Capture a dream before it fades',
    emoji: '🌙',
    deltaJson: _delta([
      {'insert': 'The dream'},
      {
        'insert': '\n',
        'attributes': {'header': 2}
      },
      {'insert': '\n\nHow it felt'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n\nRecurring elements'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n'},
    ]),
  ),
  WritingTemplate(
    name: 'Travel Log',
    description: 'Document a place and a moment',
    emoji: '✈️',
    deltaJson: _delta([
      {'insert': 'Where I am'},
      {
        'insert': '\n',
        'attributes': {'header': 2}
      },
      {'insert': '\n\nWhat I saw and did'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n\nFood & people'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n\nWould I come back?'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n'},
    ]),
  ),
  WritingTemplate(
    name: 'Goals Check-in',
    description: 'Track progress on what matters',
    emoji: '🎯',
    deltaJson: _delta([
      {'insert': 'My goals right now'},
      {
        'insert': '\n',
        'attributes': {'header': 2}
      },
      {'insert': ''},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'}
      },
      {'insert': ''},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'}
      },
      {'insert': '\nProgress since last time'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n\nNext concrete step'},
      {
        'insert': '\n',
        'attributes': {'header': 3}
      },
      {'insert': '\n'},
    ]),
  ),
];
