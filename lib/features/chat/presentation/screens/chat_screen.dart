import 'dart:async';
import 'dart:typed_data';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

import '../../domain/models/chat_message.dart';
import '../../domain/models/chat_history.dart';
import '../../data/history_service.dart';
import '../../logic/chat_service.dart';
import '../../logic/tool_handler.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoadingModel = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _isGenerating = false;
  Uint8List? _selectedImage;
  StreamSubscription? _chatSubscription;
  final HistoryService _historyService = HistoryService();
  String _currentChatId = DateTime.now().millisecondsSinceEpoch.toString();
  List<ChatHistory> _pastChats = [];
  List<Map<String, dynamic>> _installedModels = [];
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  bool _isTtsEnabled = false;
  bool _isSpeaking = false;
  bool _userHasScrolledUp = false;
  final Queue<String> _speechQueue = Queue<String>();
  String _systemPrompt = "You are Flutter Gemma. Support vision/tools.";
  late ToolHandler _toolHandler;

  final String _modelUrl =
      "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true";

  @override
  void initState() {
    super.initState();
    _toolHandler = ToolHandler(
      chatService: _chatService,
      onUpdateStatus: (status) {
        if (mounted) {
          setState(() {
            _messages.last = ChatMessage(text: status, isUser: false);
          });
        }
      },
      onToolComplete: (message) {
        if (mounted) {
          setState(() {
            _messages.last = message;
            _isGenerating = false;
          });
          _saveCurrentToHistory();
        }
      },
      onSpeak: _speak,
    );
    _loadSettings().then((_) {
      _initGemma();
      _loadHistory();
      _loadInstalledModels();
    });
  }

  // Logic methods (mostly copied but with cleaner structure)
  Future<void> _loadHistory() async {
    final histories = await _historyService.getHistories();
    setState(() => _pastChats = histories);
  }

  Future<void> _loadInstalledModels() async {
    final models = await _chatService.getInstalledModels();
    setState(() => _installedModels = models);
  }

  void _createNewChat() {
    setState(() {
      _messages.clear();
      _currentChatId = DateTime.now().millisecondsSinceEpoch.toString();
      _chatService.resetChat();
      _initGemma();
    });
  }

  void _loadChat(ChatHistory history) {
    setState(() {
      _messages.clear();
      _messages.addAll(history.messages);
      _currentChatId = history.id;
      _chatService.resetChat();
      _initGemma();
    });
    Navigator.pop(context);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _systemPrompt = prefs.getString('system_prompt') ?? _systemPrompt;
    });
  }

  Future<void> _saveSettings(String newPrompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('system_prompt', newPrompt);
    setState(() {
      _systemPrompt = newPrompt;
    });
  }

  Future<void> _initGemma() async {
    // SECURITY FIX: Do not hardcode tokens. Use environment variables.
    final hfToken = const String.fromEnvironment('HF_TOKEN');
    
    await _chatService.initialize(
      huggingFaceToken: hfToken.isEmpty ? null : hfToken,
    );

    bool hasModel = FlutterGemma.hasActiveModel();
    if (hasModel) {
      _loadModel();
    } else {
      bool isInstalled = await _chatService.isModelInstalled(ModelType.gemmaIt.name);
      if (isInstalled) {
        _loadModel();
      }
    }
  }

  Future<void> _loadModel() async {
    setState(() => _isLoadingModel = true);
    try {
      await _chatService.loadModel(
        modelType: ModelType.gemmaIt,
        supportImage: true,
      );
      await _chatService.setSystemPrompt(_systemPrompt);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading model: $e')));
    } finally {
      if (mounted) setState(() => _isLoadingModel = false);
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      await _chatService.installModel(
        modelType: ModelType.gemmaIt,
        url: _modelUrl,
        fileType: ModelFileType.task,
        onProgress: (progress) {
          setState(() => _downloadProgress = progress.toDouble() / 100);
        },
      );
      setState(() => _isDownloading = false);
      _loadModel();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() => _selectedImage = bytes);
    }
  }

  void _sendMessage() async {
    if (_controller.text.isEmpty && _selectedImage == null) return;

    final text = _controller.text;
    final image = _selectedImage;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, imageBytes: image));
      _controller.clear();
      _selectedImage = null;
      _isGenerating = true;
      _messages.add(ChatMessage(text: "", isUser: false));
    });

    _scrollToBottom();
    _speechQueue.clear();
    _flutterTts.stop();

    String fullResponse = "";
    String ttsBuffer = "";
    
    _chatSubscription = _chatService.sendMessage(text, imageBytes: image).listen(
      (chunk) async {
        if (chunk.startsWith('TOOL:')) {
          _chatSubscription?.cancel();
          await _toolHandler.handleTool(chunk, fullResponse);
          return;
        }

        fullResponse += chunk;
        ttsBuffer += chunk;

        final sentenceExp = RegExp(r'(.+?[\.\!\?])(?:\s|$)');
        var match = sentenceExp.firstMatch(ttsBuffer);
        while (match != null) {
          final sentence = match.group(1)!;
          _speak(sentence);
          ttsBuffer = ttsBuffer.substring(match.end).trimLeft();
          match = sentenceExp.firstMatch(ttsBuffer);
        }

        if (mounted) {
          setState(() {
            _messages.last = ChatMessage(text: fullResponse, isUser: false);
          });
          _scrollToBottom();
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _messages.last = ChatMessage(text: "Error: $e", isUser: false);
            _isGenerating = false;
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() => _isGenerating = false);
          if (ttsBuffer.isNotEmpty) {
            _speak(ttsBuffer);
            ttsBuffer = "";
          }
          _saveCurrentToHistory();
        }
        _chatSubscription = null;
      },
      cancelOnError: true,
    );
  }

  void _stopGenerating() {
    _chatSubscription?.cancel();
    _chatSubscription = null;
    _speechQueue.clear();
    _flutterTts.stop();
    _chatService.resetChat();
    if (mounted) {
      setState(() {
        _isGenerating = false;
        if (_messages.isNotEmpty && _messages.last.text.isEmpty && !_messages.last.isUser) {
          _messages.removeLast();
        }
      });
    }
  }

  void _saveCurrentToHistory() {
    if (_messages.isEmpty) return;
    final titleCandidate = _messages.firstWhere((m) => m.isUser, orElse: () => ChatMessage(text: "New Chat", isUser: true)).text;
    _historyService.saveChat(ChatHistory(
      id: _currentChatId,
      title: titleCandidate.length > 30 ? "${titleCandidate.substring(0, 30)}..." : titleCandidate,
      messages: _messages,
      timestamp: DateTime.now(),
    )).then((_) => _loadHistory());
  }

  void _scrollToBottom() {
    if (_userHasScrolledUp) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _speak(String text) async {
    if (!_isTtsEnabled) return;
    String cleanText = text.replaceAll(RegExp(r'[*_`#\n]'), '').trim();
    if (cleanText.isEmpty) return;
    _speechQueue.add(cleanText);
    _processSpeechQueue();
  }

  Future<void> _processSpeechQueue() async {
    if (_isSpeaking || _speechQueue.isEmpty) return;
    _isSpeaking = true;
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.awaitSpeakCompletion(true);

    while (_speechQueue.isNotEmpty) {
      if (!_isTtsEnabled) {
        _speechQueue.clear();
        break;
      }
      String nextText = _speechQueue.removeFirst();
      await _flutterTts.speak(nextText);
    }
    _isSpeaking = false;
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
    } else {
      if (await Permission.microphone.request().isGranted) {
        bool available = await _speechToText.initialize(
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              setState(() => _isListening = false);
            }
          },
        );
        if (available) {
          setState(() => _isListening = true);
          _speechToText.listen(onResult: (result) {
            setState(() {
              _controller.text = result.recognizedWords;
              _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
            });
            if (result.finalResult) setState(() => _isListening = false);
          });
        }
      }
    }
  }

  // --- UI Building Methods ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: _buildAppBar(),
      drawer: _buildHistoryDrawer(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Text("Flutter Gemma", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
      actions: [
        _buildTokenCounter(),
        IconButton(icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70), onPressed: () {
          setState(() { _messages.clear(); _chatService.resetChat(); _chatService.setSystemPrompt(_systemPrompt); });
          _saveCurrentToHistory();
        }),
        IconButton(
          icon: Icon(_isTtsEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: _isTtsEnabled ? Colors.blueAccent : Colors.white70),
          onPressed: () { setState(() => _isTtsEnabled = !_isTtsEnabled); if (!_isTtsEnabled) _flutterTts.stop(); },
        ),
        IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white70), onPressed: _showSettingsDialog),
      ],
    );
  }

  Widget _buildTokenCounter() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.token_outlined, size: 14, color: Colors.blueAccent),
            const SizedBox(width: 4),
            Text("${_chatService.totalTokens}", style: GoogleFonts.firaCode(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          if (notification.scrollDelta! < 0) { if (!_userHasScrolledUp) setState(() => _userHasScrolledUp = true); }
          if (_scrollController.position.atEdge && _scrollController.position.pixels != 0) { if (_userHasScrolledUp) setState(() => _userHasScrolledUp = false); }
        }
        return false;
      },
      child: Column(
        children: [
          if (_isDownloading) _buildDownloadProgress(),
          if (_isLoadingModel) const Padding(padding: EdgeInsets.all(20.0), child: SpinKitPulse(color: Colors.blueAccent, size: 40)),
          if (!_chatService.isInitialized && !_isDownloading && !_isLoadingModel) _buildSetupView(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: _messages.length,
              itemBuilder: (context, index) => _buildMessageItem(_messages[index], index),
            ),
          ),
          if (_selectedImage != null) _buildImagePreview(),
          _buildInputArea(),
        ],
      ),
    );
  }

  // --- Sub-widgets extracted for readability ---
  Widget _buildDownloadProgress() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
      child: Column(children: [
        Text("Downloading Flutter Gemma...", style: GoogleFonts.outfit(color: Colors.white)),
        const SizedBox(height: 12),
        ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: _downloadProgress, backgroundColor: Colors.white10, valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent), minHeight: 8)),
        const SizedBox(height: 8),
        Text("${(_downloadProgress * 100).toStringAsFixed(1)}%", style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }

  Widget _buildSetupView() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32), margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.02)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome, size: 48, color: Colors.blueAccent),
          const SizedBox(height: 24),
          Text("Experience AI Locally", style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          Text("Flutter Gemma uses Google's latest on-device models to provide a secure, private, and offline AI experience.", textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white70, height: 1.5)),
          const SizedBox(height: 32),
          ElevatedButton(onPressed: _downloadModel, style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text("Download AI Model", style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage message, int index) {
     return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) _AnimatedBotAvatar(),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              child: Column(
                crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (message.imageBytes != null)
                    Container(margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(message.imageBytes!, fit: BoxFit.cover, height: 200, width: 250))),
                  if (message.text.isNotEmpty || (message.text.isEmpty && !message.isUser && _isGenerating))
                     Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: message.isUser ? Colors.blueAccent : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: Radius.circular(message.isUser ? 16 : 0), bottomRight: Radius.circular(message.isUser ? 0 : 16)),
                        border: message.isUser ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: message.text.isEmpty && !message.isUser ? const SpinKitThreeBounce(color: Colors.white70, size: 14) : MarkdownBody(data: message.text, styleSheet: MarkdownStyleSheet(p: GoogleFonts.inter(color: Colors.white, fontSize: 15), code: GoogleFonts.firaCode(backgroundColor: Colors.black26))),
                    ),
                  if (message.searchUrl != null) 
                    Padding(padding: const EdgeInsets.only(top: 12), child: ElevatedButton.icon(onPressed: () => launchUrl(Uri.parse(message.searchUrl!), mode: LaunchMode.externalApplication), icon: const Icon(Icons.search, size: 18), label: const Text("Search on DuckDuckGo"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent.withValues(alpha: 0.2), foregroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.blueAccent, width: 0.5))))),
                ],
              ),
            ),
          ),
          if (message.isUser) Container(margin: const EdgeInsets.only(left: 12), child: CircleAvatar(backgroundColor: Colors.white.withValues(alpha: 0.1), child: const Icon(Icons.person, color: Colors.white70, size: 20))),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      padding: const EdgeInsets.all(12), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_selectedImage!, width: 60, height: 60, fit: BoxFit.cover)),
        const SizedBox(width: 12), const Text("Image attached", style: TextStyle(color: Colors.white70)),
        const Spacer(), IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => setState(() => _selectedImage = null)),
      ]),
    );
  }

  Widget _buildInputArea() {
    bool canSend = _chatService.isInitialized && !_isGenerating;
    return Container(
      padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1E293B), border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
      child: SafeArea(child: Row(children: [
        IconButton(icon: Icon(Icons.add_a_photo_outlined, color: canSend ? Colors.blueAccent : Colors.grey), onPressed: canSend ? _pickImage : null),
        Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(24)), child: TextField(controller: _controller, enabled: canSend, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Ask anything...", hintStyle: TextStyle(color: Colors.white38), border: InputBorder.none)))),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _isGenerating ? _stopGenerating : (canSend ? (_controller.text.isNotEmpty || _selectedImage != null ? _sendMessage : _toggleListening) : null),
          child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _isGenerating ? Colors.redAccent.withValues(alpha: 0.2) : (canSend ? (_isListening ? Colors.redAccent : Colors.blueAccent) : Colors.grey), shape: BoxShape.circle), child: _isGenerating ? const Icon(Icons.stop_rounded, color: Colors.redAccent) : (_isListening ? const SpinKitWave(color: Colors.white, size: 24) : Icon(_controller.text.isNotEmpty || _selectedImage != null ? Icons.send_rounded : Icons.mic_rounded, color: Colors.white))),
        ),
      ])),
    );
  }

  Widget _buildHistoryDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(20), child: ElevatedButton.icon(onPressed: _createNewChat, icon: const Icon(Icons.add), label: const Text("New Chat"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
        Expanded(child: ListView.builder(itemCount: _pastChats.length, itemBuilder: (context, index) {
          final chat = _pastChats[index]; final isCurrent = chat.id == _currentChatId;
          return ListTile(selected: isCurrent, selectedTileColor: Colors.white10, title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isCurrent ? Colors.blueAccent : Colors.white70)), subtitle: Text(DateFormat('MMM d, HH:mm').format(chat.timestamp), style: const TextStyle(color: Colors.white24, fontSize: 10)), onTap: () => _loadChat(chat));
        })),
        ListTile(leading: const Icon(Icons.delete_forever, color: Colors.redAccent), title: const Text("Clear History", style: TextStyle(color: Colors.redAccent)), onTap: () { _historyService.clearAllHistories(); _loadHistory(); }),
      ])),
    );
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: _systemPrompt);
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E293B), title: const Text("System Prompt"),
      content: TextField(controller: controller, maxLines: 5, decoration: const InputDecoration(filled: true, fillColor: Colors.black26)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(onPressed: () { _saveSettings(controller.text); Navigator.pop(context); _createNewChat(); }, child: const Text("Save & Restart")),
      ],
    ));
  }
}

class _AnimatedBotAvatar extends StatefulWidget {
  @override
  State<_AnimatedBotAvatar> createState() => _AnimatedBotAvatarState();
}

class _AnimatedBotAvatarState extends State<_AnimatedBotAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _controller; late Animation<double> _scaleAnimation;
  @override
  void initState() { super.initState(); _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true); _scaleAnimation = Tween<double>(begin: 0.95, end: 1.1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnimation, child: Container(margin: const EdgeInsets.only(right: 12), height: 40, width: 40, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Colors.blueAccent, Colors.cyanAccent])), child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20)));
  }
}
