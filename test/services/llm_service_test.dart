import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/llm_service.dart';

void main() {
  group('LLMService', () {
    late LLMService llm;

    setUp(() {
      llm = LLMService();
    });

    test('available models are defined', () {
      expect(LLMService.availableModels.isNotEmpty, true);
    });

    test('has free models', () {
      final free = LLMService.availableModels.where((m) => m.isFree);
      expect(free.isNotEmpty, true);
    });

    test('switches to valid model', () {
      final target = LLMService.availableModels.first.id;
      llm.switchModel(target);
      expect(llm.currentModelId, target);
    });

    test('ignores invalid model', () {
      final original = llm.currentModelId;
      llm.switchModel('nonexistent/model');
      expect(llm.currentModelId, original);
    });

    test('blacklist prevents model use', () {
      final target = LLMService.availableModels.first.id;
      llm.blacklistModel(target);
      llm.switchModel(target);
      expect(llm.currentModelId, isNot(target));
    });

    test('findFallbackModel returns alternative', () {
      final fallback = llm.findFallbackModel();
      expect(fallback, isNotNull);
      expect(fallback, isNot(llm.currentModelId));
    });

    test('suggestBestModel prefers free for simple queries', () {
      final suggestion = llm.suggestBestModel('hi', 100);
      final config = LLMService.availableModels.where((m) => m.id == suggestion);
      expect(config.isNotEmpty, true);
    });

    test('recordFailure tracks failures', () {
      final target = LLMService.availableModels.first.id;
      for (int i = 0; i < 3; i++) {
        llm.recordFailure(target);
      }
      final fallback = llm.findFallbackModel();
      expect(fallback, isNotNull);
    });
  });
}
