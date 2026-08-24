import 'package:flutter_test/flutter_test.dart';
import 'package:journal/widgets/entry_card.dart';

void main() {
  test('writing time shown on a feed card', () {
    expect(formatWritingTime(0), '0s');
    expect(formatWritingTime(45), '45s');
    expect(formatWritingTime(60), '1m');
    expect(formatWritingTime(12 * 60 + 30), '12m');
    expect(formatWritingTime(3600), '1h 0m');
    expect(formatWritingTime(2 * 3600 + 5 * 60), '2h 5m');
  });
}
