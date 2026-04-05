import 'dart:typed_data';

class ChatMessage {
  final String text;
  final bool isUser;
  final Uint8List? imageBytes;
  final String? searchUrl;
  final List<SearchSource>? searchSources;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.imageBytes,
    this.searchUrl,
    this.searchSources,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'searchUrl': searchUrl,
    'searchSources': searchSources?.map((s) => s.toJson()).toList(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'],
      isUser: json['isUser'],
      searchUrl: json['searchUrl'],
      searchSources: (json['searchSources'] as List?)
          ?.map((s) => SearchSource.fromJson(s))
          .toList(),
    );
  }
}

class SearchSource {
  final String title;
  final String url;

  const SearchSource({required this.title, required this.url});

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
  };

  factory SearchSource.fromJson(Map<String, dynamic> json) {
    return SearchSource(
      title: json['title'],
      url: json['url'],
    );
  }
}
