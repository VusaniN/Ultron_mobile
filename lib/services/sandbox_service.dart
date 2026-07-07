import 'package:flutter/foundation.dart';

enum PermissionLevel { allowed, confirm, denied }

enum ActionType {
  joke,
  time,
  stats,
  volume,
  launch,
  search,
  chat,
  memory,
  webSearch,
  webFetch,
  readDocument,
  writeMemory,
  executeSkill,
  calculate,
}

class SandboxService extends ChangeNotifier {
  bool _chatOnly = false;

  final Map<ActionType, PermissionLevel> _permissions = {
    ActionType.joke: PermissionLevel.allowed,
    ActionType.time: PermissionLevel.allowed,
    ActionType.stats: PermissionLevel.allowed,
    ActionType.volume: PermissionLevel.confirm,
    ActionType.launch: PermissionLevel.confirm,
    ActionType.search: PermissionLevel.allowed,
    ActionType.chat: PermissionLevel.allowed,
    ActionType.memory: PermissionLevel.allowed,
    ActionType.webSearch: PermissionLevel.allowed,
    ActionType.webFetch: PermissionLevel.allowed,
    ActionType.readDocument: PermissionLevel.allowed,
    ActionType.writeMemory: PermissionLevel.allowed,
    ActionType.executeSkill: PermissionLevel.allowed,
    ActionType.calculate: PermissionLevel.allowed,
  };

  bool get chatOnly => _chatOnly;

  void toggleChatOnly() {
    _chatOnly = !_chatOnly;
    notifyListeners();
  }

  PermissionLevel getPermission(ActionType action) =>
      _permissions[action] ?? PermissionLevel.allowed;

  void setPermission(ActionType action, PermissionLevel level) {
    _permissions[action] = level;
    notifyListeners();
  }

  bool canExecute(ActionType action) {
    if (_chatOnly && action != ActionType.chat && action != ActionType.memory) {
      return false;
    }
    return _permissions[action] != PermissionLevel.denied;
  }

  bool needsConfirmation(ActionType action) {
    if (_chatOnly) return false;
    return _permissions[action] == PermissionLevel.confirm;
  }
}
