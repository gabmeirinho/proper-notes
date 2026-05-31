import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:proper_notes/infrastructure/ai/openai_note_ai_service.dart';
import 'package:proper_notes/infrastructure/auth/secret_store.dart';

void main() {
  test('uploads audio to mini transcribe model and summarizes transcript',
      () async {
    final tempDirectory =
        await Directory.systemTemp.createTemp('openai_note_ai_test_');
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final audioFile = File('${tempDirectory.path}/recording.m4a');
    await audioFile.writeAsBytes(<int>[1, 2, 3]);

    final requestedUrls = <Uri>[];
    final client = _FakeOpenAiClient((request) async {
      requestedUrls.add(request.url);

      if (request is http.MultipartRequest) {
        expect(request.headers['Authorization'], 'Bearer openai-key');
        expect(request.url.path, '/v1/audio/transcriptions');
        expect(request.fields['model'], 'gpt-4o-mini-transcribe');
        expect(request.fields['response_format'], 'json');
        expect(request.files.single.field, 'file');
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"text":"We discussed sync safety."}')),
          200,
        );
      }

      final body = jsonDecode((request as http.Request).body);
      expect(request.headers['Authorization'], 'Bearer deepseek-key');
      expect(request.url.host, 'api.deepseek.com');
      expect(request.url.path, '/chat/completions');
      expect(body['model'], 'deepseek-v4-flash');
      expect(body['thinking'], <String, String>{'type': 'disabled'});
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            '{"choices":[{"message":{"content":"- Sync safety"}}]}',
          ),
        ),
        200,
      );
    });

    final service = OpenAiNoteAiService(
      secretStore: _MemorySecretStore(<String, String>{
        'openai.api_key': 'openai-key',
        'deepseek.api_key': 'deepseek-key',
      }),
      httpClient: client,
    );

    final result = await service.transcribeAndSummarize(audioFile);

    expect(result.transcript, 'We discussed sync safety.');
    expect(result.summary, '- Sync safety');
    expect(
      requestedUrls.map((url) => url.path),
      <String>['/v1/audio/transcriptions', '/chat/completions'],
    );
  });
}

class _FakeOpenAiClient extends http.BaseClient {
  _FakeOpenAiClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}

class _MemorySecretStore implements SecretStore {
  _MemorySecretStore(this._values);

  final Map<String, String> _values;

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({
    required String key,
    required String value,
  }) async {
    _values[key] = value;
  }
}
