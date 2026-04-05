import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/chat_history.dart';

class HistoryService {
  static const String _key = 'chat_histories';

  Future<void> saveChat(ChatHistory chat) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> historyStrings = prefs.getStringList(_key) ?? [];
    
    // Update existing or add new
    int index = historyStrings.indexWhere((s) {
      try {
        return json.decode(s)['id'] == chat.id;
      } catch (e) {
        return false;
      }
    });

    if (index != -1) {
      historyStrings[index] = json.encode(chat.toJson());
    } else {
      historyStrings.insert(0, json.encode(chat.toJson()));
    }
    
    await prefs.setStringList(_key, historyStrings);
  }

  Future<List<ChatHistory>> getHistories() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> historyStrings = prefs.getStringList(_key) ?? [];
    return historyStrings.map((s) {
      try {
        return ChatHistory.fromJson(json.decode(s));
      } catch (e) {
        // Handle corrupted history data
        return null;
      }
    }).whereType<ChatHistory>().toList();
  }

  Future<void> deleteHistory(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> historyStrings = prefs.getStringList(_key) ?? [];
    historyStrings.removeWhere((s) {
       try {
        return json.decode(s)['id'] == id;
      } catch (e) {
        return false;
      }
    });
    await prefs.setStringList(_key, historyStrings);
  }

  Future<void> clearAllHistories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
