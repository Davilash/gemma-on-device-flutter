import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/tool.dart';
import '../data/web_search_service.dart';

class ChatService {
  InferenceChat? _chat;
  InferenceModel? _model;
  bool _isInitialized = false;
  final WebSearchService _webSearch = WebSearchService();
  int _totalTokens = 0;

  final List<Tool> _tools = [
     const Tool(
      name: 'make_call',
      description: 'Call contact',
      parameters: {
        'type': 'object',
        'properties': {
          'phoneNumber': {'type': 'string'},
        },
        'required': ['phoneNumber'],
      },
    ),
    const Tool(
      name: 'search_web',
      description: 'Web search',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      },
    ),
    const Tool(
      name: 'set_alarm',
      description: 'Set alarm',
      parameters: {
        'type': 'object',
        'properties': {
          'hour': {'type': 'integer'},
          'minute': {'type': 'integer'},
        },
        'required': ['hour', 'minute'],
      },
    ),
    const Tool(
      name: 'open_app',
      description: 'Open app',
      parameters: {
        'type': 'object',
        'properties': {
          'appName': {'type': 'string'},
        },
        'required': ['appName'],
      },
    ),
  ];

  bool get isInitialized => _isInitialized;
  int get totalTokens => _totalTokens;

  void _addTokens(String text) {
    // Basic approximate tokenization: ~1 token per 4 chars for English
    _totalTokens += (text.length / 4).ceil();
  }

  void _resetTokens() => _totalTokens = 0;

  Future<WebSearchResult> searchWeb(String query) => _webSearch.search(query);

  Future<void> initialize({String? huggingFaceToken}) async {
    FlutterGemma.initialize(huggingFaceToken: huggingFaceToken);
  }

  Future<bool> isModelInstalled(String modelId) async {
    return FlutterGemma.isModelInstalled(modelId);
  }

  Future<void> installModel({
    required ModelType modelType,
    required String url,
    required void Function(int) onProgress,
    ModelFileType fileType = ModelFileType.task,
  }) async {
    await FlutterGemma.installModel(
      modelType: modelType,
      fileType: fileType,
    ).fromNetwork(url).withProgress(onProgress).install();
  }

  Future<void> loadModel({
    ModelType modelType = ModelType.general,
    bool supportImage = false,
  }) async {
    try {
      _model = await FlutterGemma.getActiveModel(
        supportImage: supportImage,
        maxTokens: 4096,
      );
      _chat = await _model!.createChat(
        modelType: modelType,
        supportImage: supportImage,
        tools: _tools, 
        supportsFunctionCalls: true,
      );
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  Stream<String> sendMessage(String text, {Uint8List? imageBytes}) async* {
    if (_chat == null) {
      yield 'Error: Model not loaded. Please download or reload the model.';
      return;
    }

    try {
      Message message;
      if (imageBytes != null) {
        if (text.isEmpty) {
          message = Message.imageOnly(imageBytes: imageBytes, isUser: true);
        } else {
          message = Message.withImage(
            text: text,
            imageBytes: imageBytes,
            isUser: true,
          );
        }
      } else {
        message = Message.text(text: text, isUser: true);
      }

      await _chat!.addQuery(message);
      final response = _chat!.generateChatResponseAsync();

      bool receivedResponse = false;
      await for (final chunk in response) {
        if (chunk is TextResponse) {
          if (chunk.token.isNotEmpty) {
            receivedResponse = true;
            _addTokens(chunk.token);
            yield chunk.token;
          }
        } else if (chunk is FunctionCallResponse) {
          receivedResponse = true;
          yield 'TOOL:${chunk.name}:${chunk.args.values.join(',')}';
        }
      }

      if (!receivedResponse) {
        await _chat?.clearHistory();
        yield 'ERROR: Code 13 (Mem) - Session reset to restore stability.';
      }
    } catch (e) {
      debugPrint('LiteRT Error: $e');
      await _chat?.clearHistory();
      yield 'Error: $e (Session Reset)';
    }
  }

  Future<void> setSystemPrompt(String prompt) async {
    if (_chat == null) return;
    await _chat!.clearHistory();
    final systemMessage = Message(text: prompt, isUser: false);
    await _chat!.addQuery(systemMessage);
  }

  void resetChat() {
    _chat?.clearHistory();
    _resetTokens();
  }

  Future<List<Map<String, dynamic>>> getInstalledModels() async {
    // List of common model names to check
    final List<String> modelNames = [
      'gemma-2b-it',
      'gemma-7b-it',
      'gemma-4-e2b-it',
      'gemma-4-E2B-it',
      'gemma-3n-e2b-it',
      'gemmaIt',
    ];
    
    List<Map<String, dynamic>> installed = [];
    for (var name in modelNames) {
      if (await FlutterGemma.isModelInstalled(name)) {
        installed.add({'name': name.toUpperCase(), 'id': name});
      }
    }
    return installed;
  }
}
