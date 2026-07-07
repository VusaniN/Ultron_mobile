import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:external_app_launcher/external_app_launcher.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:http/http.dart' as http;
import '../core/logger.dart';

class DeviceService {
  final Logger _log = Logger('DeviceService');
  final Battery _battery = Battery();

  String getJoke() {
    final jokes = [
      "Why do Java developers wear glasses? Because they can't C#.",
      "There are only 10 types of people: those who understand binary and those who don't.",
      "A SQL query walks into a bar, sees two tables, and asks... can I join you?",
      "Why did the developer go broke? Because he used up all his cache.",
      "My code doesn't have bugs — it just develops random features.",
      "How many programmers to change a light bulb? None. That's a hardware problem.",
      "I'd tell you a UDP joke, but you might not get it.",
      "What's an AI's favorite snack? Microchips!",
    ];
    return jokes[DateTime.now().millisecond % jokes.length];
  }

  String getTime() {
    final now = DateTime.now();
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final min = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final weekday = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][now.weekday - 1];
    final month = ['January','February','March','April','May','June','July','August','September','October','November','December'][now.month - 1];
    return "It's $hour:$min $ampm on $weekday, ${month} ${now.day}.";
  }

  Future<String> getBatteryStatus() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final charging = state == BatteryState.charging ? ' — charging' : '';
      String status;
      if (level > 75) status = "Battery's solid at $level%$charging.";
      else if (level > 40) status = "Battery at $level%$charging.";
      else if (level > 15) status = "Battery getting low — $level%$charging.";
      else status = "Battery critical: $level%! Plug in soon.";
      _log.i('Battery: $level% $charging');
      return status;
    } catch (e) {
      _log.e('Battery read failed: $e');
      return "Couldn't read battery info.";
    }
  }

  Future<String> setVolume(String params) async {
    try {
      final vol = (double.tryParse(params) ?? 50.0).clamp(0, 100);
      VolumeController().setVolume(vol / 100);
      _log.i('Volume set to ${vol.toInt()}%');
      return "Volume set to ${vol.toInt()}%.";
    } catch (e) {
      _log.e('Volume control failed: $e');
      return "Couldn't adjust volume.";
    }
  }

  Future<String> launchApp(String appName) async {
    try {
      if (Platform.isAndroid) {
        final apps = await InstalledApps.getInstalledApps();
        final target = apps.firstWhere(
          (app) => app.name?.toLowerCase().contains(appName.toLowerCase()) ?? false,
          orElse: () => throw Exception("App not found"),
        );
        await InstalledApps.startApp(target.packageName!);
        _log.i('Launched app: ${target.name}');
        return "Opening ${target.name}.";
      } else {
        await LaunchApp.openApp(androidPackageName: appName, iosUrlScheme: appName);
        return "Launching $appName.";
      }
    } catch (e) {
      _log.w('Launch failed for "$appName": $e');
      return "Couldn't find an app matching '$appName'.";
    }
  }

  Future<String> searchWeb(String query) async {
    try {
      final url = Uri.parse("https://html.duckduckgo.com/html/?q=${Uri.encodeComponent(query)}");
      final res = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Mobile)',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return "Search failed — try again later.";

      final results = <Map<String, String>>[];
      final titleRegex = RegExp(r'<a rel="nofollow" class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>', dotAll: true);
      final snippetRegex = RegExp(r'<a class="result__snippet"[^>]*>(.*?)</a>', dotAll: true);

      final titles = titleRegex.allMatches(res.body);
      final snippets = snippetRegex.allMatches(res.body).toList();

      int count = 0;
      for (final match in titles) {
        if (count >= 3) break;
        final title = _stripHtml(match.group(2) ?? '').trim();
        final snippet = count < snippets.length ? _stripHtml(snippets[count].group(1) ?? '').trim() : '';
        if (title.isNotEmpty) {
          results.add({'title': title, 'snippet': snippet});
          count++;
        }
      }

      if (results.isEmpty) return "No results found for '$query'.";
      final buffer = StringBuffer("Here's what I found for '$query':\n\n");
      for (int i = 0; i < results.length; i++) {
        buffer.writeln("${i + 1}. ${results[i]['title']}");
        if (results[i]['snippet']!.isNotEmpty) {
          buffer.writeln("   ${results[i]['snippet']}");
        }
      }
      return buffer.toString().trim();
    } catch (e) {
      _log.e('Web search failed: $e');
      return "Couldn't reach the internet. Check your connection.";
    }
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ');
  }
}
