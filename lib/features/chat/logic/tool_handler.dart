import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../logic/chat_service.dart';
import '../domain/models/chat_message.dart';

class ToolHandler {
  final ChatService chatService;
  final Function(String) onUpdateStatus;
  final Function(ChatMessage) onToolComplete;
  final Function(String) onSpeak;

  ToolHandler({
    required this.chatService,
    required this.onUpdateStatus,
    required this.onToolComplete,
    required this.onSpeak,
  });

  Future<void> handleTool(String toolInfo, String currentFullResponse) async {
    final parts = toolInfo.split(':');
    if (parts.length < 2) return;
    
    final name = parts[1];
    final arg = parts.length > 2 ? parts[2] : "";

    switch (name) {
      case 'make_call':
        await _handleMakeCall(arg, currentFullResponse);
        break;
      case 'search_web':
        await _handleSearchWeb(arg, currentFullResponse);
        break;
      case 'set_alarm':
        await _handleSetAlarm(arg, currentFullResponse);
        break;
      case 'open_app':
        await _handleOpenApp(arg, currentFullResponse);
        break;
    }
  }

  Future<void> _handleMakeCall(String destination, String currentFullResponse) async {
    String finalNumber = destination;

    if (RegExp(r'[a-zA-Z]').hasMatch(destination)) {
      if (await Permission.contacts.request().isGranted) {
        onUpdateStatus("Searching '$destination'...");
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        for (final contact in contacts) {
          if (contact.displayName.toLowerCase().contains(destination.toLowerCase())) {
            if (contact.phones.isNotEmpty) {
              finalNumber = contact.phones.first.number.replaceAll(RegExp(r'[^\d+]'), '');
              break;
            }
          }
        }
      }
    }
    
    final Uri telUri = Uri.parse('tel:$finalNumber');
    if (await canLaunchUrl(telUri)) {
      await launchUrl(telUri);
      final msg = "Sure! Dialling $destination...";
      onToolComplete(ChatMessage(
        text: (currentFullResponse.isNotEmpty ? "$currentFullResponse\n\n" : "") + msg,
        isUser: false,
      ));
      onSpeak(msg);
    }
  }

  Future<void> _handleSearchWeb(String query, String currentFullResponse) async {
    onUpdateStatus("Searching for **$query**...");
    try {
      final result = await chatService.searchWeb(query);
      final sources = result.sources.map((s) => SearchSource(title: s.title, url: s.url)).toList();
      onToolComplete(ChatMessage(
        text: (currentFullResponse.isNotEmpty ? "$currentFullResponse\n\n" : "") + "**Web result**\n\n${result.summary}",
        isUser: false,
        searchSources: sources,
        searchUrl: 'https://duckduckgo.com/?q=${Uri.encodeComponent(query)}',
      ));
    } catch (e) {
      onToolComplete(ChatMessage(
        text: (currentFullResponse.isNotEmpty ? "$currentFullResponse\n\n" : "") + "Web search failed: $e",
        isUser: false,
        searchUrl: 'https://duckduckgo.com/?q=${Uri.encodeComponent(query)}',
      ));
    }
  }

  Future<void> _handleSetAlarm(String arg, String currentFullResponse) async {
    final subParts = arg.split(',');
    final hour = int.tryParse(subParts[0]) ?? 0;
    final minute = subParts.length > 1 ? (int.tryParse(subParts[1]) ?? 0) : 0;
    
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: {
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.SKIP_UI': false
      },
    );
    await intent.launch();
    
    final msg = "Setting alarm for $hour:${minute.toString().padLeft(2, '0')}.";
    onToolComplete(ChatMessage(
      text: (currentFullResponse.isNotEmpty ? "$currentFullResponse\n\n" : "") + msg,
      isUser: false,
    ));
    onSpeak(msg);
  }

  Future<void> _handleOpenApp(String appName, String currentFullResponse) async {
    List<AppInfo> apps = await InstalledApps.getInstalledApps();
    for (var app in apps) {
      if (app.name.toLowerCase().contains(appName.toLowerCase())) {
        await InstalledApps.startApp(app.packageName);
        final msg = "Opened $appName!";
        onToolComplete(ChatMessage(
          text: (currentFullResponse.isNotEmpty ? "$currentFullResponse\n\n" : "") + msg,
          isUser: false,
        ));
        onSpeak(msg);
        return;
      }
    }
    onToolComplete(ChatMessage(
      text: (currentFullResponse.isNotEmpty ? "$currentFullResponse\n\n" : "") + "I couldn't find '$appName'.",
      isUser: false,
    ));
  }
}
