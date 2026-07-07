import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/intent_service.dart';

void main() {
  group('IntentService', () {
    late IntentService intent;

    setUp(() {
      intent = IntentService();
    });

    test('classifies joke command', () {
      final result = intent.classify('Tell me a joke');
      expect(result.isDeviceCommand, true);
      expect(result.action, 'joke');
      expect(result.isHighConfidence, true);
    });

    test('classifies time command', () {
      final result = intent.classify('What time is it?');
      expect(result.isDeviceCommand, true);
      expect(result.action, 'time');
    });

    test('classifies battery command', () {
      final result = intent.classify('Check battery');
      expect(result.isDeviceCommand, true);
      expect(result.action, 'battery');
    });

    test('classifies launch command', () {
      final result = intent.classify('open spotify');
      expect(result.isDeviceCommand, true);
      expect(result.action, 'launch');
    });

    test('classifies search command', () {
      final result = intent.classify('search for Flutter tutorials');
      expect(result.isDeviceCommand, true);
      expect(result.action, 'search');
    });

    test('classifies conversational query', () {
      final result = intent.classify('What is the meaning of life?');
      expect(result.isConversational, true);
      expect(result.isHighConfidence, true);
    });

    test('classifies short greeting as conversational', () {
      final result = intent.classify('Hi');
      expect(result.isConversational, true);
    });

    test('classifies memory recall', () {
      final result = intent.classify('What do you remember?');
      expect(result.isMemory, true);
    });

    test('classifies memory save', () {
      final result = intent.classify('remember that I like pizza');
      expect(result.isMemory, true);
    });
  });
}
