import 'dart:convert';
import 'package:http/http.dart' as http;

class WebSearchItem {
  final String title;
  final String url;

  const WebSearchItem({required this.title, required this.url});
}

class WebSearchResult {
  final String summary;
  final List<WebSearchItem> sources;

  const WebSearchResult({required this.summary, required this.sources});
}

class WebSearchService {
  static const String _base =
      'https://api.duckduckgo.com/?format=json&no_html=1&no_redirect=1&q=';

  Future<WebSearchResult> search(String query) async {
    try {
      final uri = Uri.parse('$_base${Uri.encodeComponent(query)}');
      final res =
          await http.get(uri, headers: const {'Accept': 'application/json'});

      if (res.statusCode != 200) {
        return WebSearchResult(
          summary: 'Web search failed (HTTP ${res.statusCode}).',
          sources: const [],
        );
      }

      final dynamic decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return const WebSearchResult(
          summary: 'Web search returned an unexpected response.',
          sources: [],
        );
      }

      String? abstractText = (decoded['AbstractText'] as String?)?.trim();
      String? abstractUrl = (decoded['AbstractURL'] as String?)?.trim();

      final items = <WebSearchItem>[];
      if (abstractText != null &&
          abstractText.isNotEmpty &&
          abstractUrl != null &&
          abstractUrl.isNotEmpty) {
        items.add(WebSearchItem(title: abstractText, url: abstractUrl));
      }

      void addRelated(dynamic node) {
        if (node is Map<String, dynamic>) {
          final text = (node['Text'] as String?)?.trim();
          final url = (node['FirstURL'] as String?)?.trim();
          if (text != null && text.isNotEmpty && url != null && url.isNotEmpty) {
            items.add(WebSearchItem(title: text, url: url));
          }
          final topics = node['Topics'];
          if (topics is List) {
            for (final t in topics) {
              addRelated(t);
            }
          }
        }
      }

      final related = decoded['RelatedTopics'];
      if (related is List) {
        for (final t in related) {
          addRelated(t);
        }
      }

      // De-dup URLs and cap for UI.
      final seen = <String>{};
      final sources = <WebSearchItem>[];
      for (final it in items) {
        if (seen.add(it.url)) sources.add(it);
        if (sources.length >= 5) break;
      }

      if (abstractText != null && abstractText.isNotEmpty) {
        return WebSearchResult(
          summary: abstractText,
          sources: sources,
        );
      }

      if (sources.isEmpty) {
        return const WebSearchResult(
          summary:
              "I couldn't find a good instant answer. Try a more specific query.",
          sources: [],
        );
      }

      return WebSearchResult(
        summary:
            'Here are relevant sources I found. If you tell me what you want from them, I can summarize.',
        sources: sources,
      );
    } catch (e) {
      return WebSearchResult(
        summary: 'Error performing web search: $e',
        sources: const [],
      );
    }
  }
}
