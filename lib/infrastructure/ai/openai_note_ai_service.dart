import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../features/ai/domain/note_ai_service.dart';
import '../auth/secret_store.dart';

class OpenAiNoteAiService implements NoteAiService {
  OpenAiNoteAiService({
    required SecretStore secretStore,
    http.Client? httpClient,
    Uri? openAiBaseUri,
    Uri? deepSeekBaseUri,
  })  : _secretStore = secretStore,
        _httpClient = httpClient ?? http.Client(),
        _openAiBaseUri =
            openAiBaseUri ?? Uri.parse('https://api.openai.com/v1/'),
        _deepSeekBaseUri =
            deepSeekBaseUri ?? Uri.parse('https://api.deepseek.com/');

  static const String _openAiApiKeySecretKey = 'openai.api_key';
  static const String _deepSeekApiKeySecretKey = 'deepseek.api_key';
  static const String _transcriptionModel = 'gpt-4o-mini-transcribe';
  static const String _summaryModel = 'deepseek-v4-flash';

  final SecretStore _secretStore;
  final http.Client _httpClient;
  final Uri _openAiBaseUri;
  final Uri _deepSeekBaseUri;

  @override
  Future<bool> hasTranscriptionApiKey() async {
    final apiKey = await _readSecret(_openAiApiKeySecretKey);
    return apiKey != null;
  }

  @override
  Future<bool> hasSummaryApiKey() async {
    final apiKey = await _readSecret(_deepSeekApiKeySecretKey);
    return apiKey != null;
  }

  @override
  Future<void> saveTranscriptionApiKey(String apiKey) {
    return _saveApiKey(
      secretKey: _openAiApiKeySecretKey,
      apiKey: apiKey,
    );
  }

  @override
  Future<void> saveSummaryApiKey(String apiKey) {
    return _saveApiKey(
      secretKey: _deepSeekApiKeySecretKey,
      apiKey: apiKey,
    );
  }

  Future<void> _saveApiKey({
    required String secretKey,
    required String apiKey,
  }) {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'API key cannot be empty.');
    }

    return _secretStore.write(
      key: secretKey,
      value: trimmed,
    );
  }

  @override
  Future<AiNoteResult> transcribeAndSummarize(File audioFile) async {
    final transcript = await _transcribe(audioFile);
    final summary = await _summarize(transcript);
    return AiNoteResult(
      transcript: transcript,
      summary: summary,
    );
  }

  Future<String> _transcribe(File audioFile) async {
    final apiKey = await _requireSecret(
      key: _openAiApiKeySecretKey,
      label: 'OpenAI',
    );
    final request = http.MultipartRequest(
      'POST',
      _openAiBaseUri.resolve('audio/transcriptions'),
    )
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = _transcriptionModel
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenAiNoteAiException(_errorMessageFromResponse(response));
    }

    final payload = jsonDecode(response.body);
    final transcript = payload is Map<String, dynamic> ? payload['text'] : null;
    if (transcript is! String || transcript.trim().isEmpty) {
      throw const OpenAiNoteAiException('OpenAI returned an empty transcript.');
    }

    return transcript.trim();
  }

  Future<String> _summarize(String transcript) async {
    final apiKey = await _requireSecret(
      key: _deepSeekApiKeySecretKey,
      label: 'DeepSeek',
    );
    final response = await _httpClient.post(
      _deepSeekBaseUri.resolve('chat/completions'),
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'model': _summaryModel,
        'messages': <Object>[
          <String, Object>{
            'role': 'system',
            'content':
                'Summarize the transcript for a personal note-taking app. '
                    'Preserve decisions, facts, and action items. '
                    'Return concise Markdown only.',
          },
          <String, Object>{
            'role': 'user',
            'content': transcript,
          },
        ],
        'thinking': <String, String>{
          'type': 'disabled',
        },
        'stream': false,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenAiNoteAiException(_errorMessageFromResponse(response));
    }

    final payload = jsonDecode(response.body);
    final outputText = payload is Map<String, dynamic>
        ? _extractChatCompletionText(payload)
        : null;
    if (outputText == null || outputText.trim().isEmpty) {
      throw const OpenAiNoteAiException('DeepSeek returned an empty summary.');
    }

    return outputText.trim();
  }

  String? _extractChatCompletionText(Map<String, dynamic> payload) {
    final choices = payload['choices'];
    if (choices is! List<dynamic> || choices.isEmpty) {
      return null;
    }

    final firstChoice = choices.first;
    final message =
        firstChoice is Map<String, dynamic> ? firstChoice['message'] : null;
    final content = message is Map<String, dynamic> ? message['content'] : null;
    return content is String && content.isNotEmpty ? content : null;
  }

  Future<String?> _readSecret(String key) async {
    final apiKey = await _secretStore.read(key);
    final trimmed = apiKey?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<String> _requireSecret({
    required String key,
    required String label,
  }) async {
    final apiKey = await _readSecret(key);
    if (apiKey == null) {
      throw OpenAiNoteAiException('$label API key is not configured.');
    }
    return apiKey;
  }

  String _errorMessageFromResponse(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      final error = payload is Map<String, dynamic> ? payload['error'] : null;
      final message = error is Map<String, dynamic> ? error['message'] : null;
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    } catch (_) {
      // Fall through to a generic response summary.
    }
    return 'OpenAI request failed with status ${response.statusCode}.';
  }
}

class OpenAiNoteAiException implements Exception {
  const OpenAiNoteAiException(this.message);

  final String message;

  @override
  String toString() => message;
}
