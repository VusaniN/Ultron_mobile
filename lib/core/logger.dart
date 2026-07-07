import 'dart:io';

enum LogLevel { debug, info, warn, error }

class Logger {
  final String tag;
  static LogLevel _minLevel = LogLevel.debug;
  static bool _enabled = true;
  static final List<String> _buffer = [];
  static const int _maxBuffer = 500;

  Logger(this.tag);

  static void setMinLevel(LogLevel level) => _minLevel = level;
  static void setEnabled(bool enabled) => _enabled = enabled;

  static List<String> getRecentLogs([int count = 50]) {
    if (_buffer.length <= count) return List.from(_buffer);
    return _buffer.sublist(_buffer.length - count);
  }

  void _log(LogLevel level, String message) {
    if (!_enabled || level.index < _minLevel.index) return;
    final timestamp = DateTime.now().toIso8601String().split('T').last;
    final line = '[$timestamp][${level.name.toUpperCase()}][$tag] $message';
    _buffer.add(line);
    if (_buffer.length > _maxBuffer) _buffer.removeAt(0);

    if (level == LogLevel.error) {
      stderr.writeln(line);
    } else {
      stdout.writeln(line);
    }
  }

  void d(String message) => _log(LogLevel.debug, message);
  void i(String message) => _log(LogLevel.info, message);
  void w(String message) => _log(LogLevel.warn, message);
  void e(String message) => _log(LogLevel.error, message);
}
