import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/core/token_estimator.dart';

void main() {
  group('TokenEstimator', () {
    late TokenEstimator estimator;

    setUp(() {
      estimator = TokenEstimator();
    });

    test('estimates tokens for empty string', () {
      expect(estimator.estimate(''), 0);
    });

    test('estimates tokens for short text', () {
      final count = estimator.estimate('Hello world');
      expect(count, greaterThan(0));
      expect(count, lessThan(10));
    });

    test('estimates tokens for long text', () {
      final long = 'Hello world ' * 100;
      final count = estimator.estimate(long);
      expect(count, greaterThan(20));
    });

    test('truncateToLimit keeps recent messages', () {
      final messages = [
        {'role': 'user', 'content': 'a'},
        {'role': 'assistant', 'content': 'b'},
        {'role': 'user', 'content': 'c'},
        {'role': 'assistant', 'content': 'd'},
      ];
      final result = estimator.truncateToLimit(messages, 1000);
      expect(result.length, greaterThan(0));
    });

    test('truncateToLimit returns empty for very small limit', () {
      final messages = [
        {'role': 'user', 'content': 'Hello, how are you?'},
      ];
      final result = estimator.truncateToLimit(messages, 10);
      expect(result.length, 0);
    });
  });
}
