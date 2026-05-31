import 'dart:io';

class AiNoteResult {
  const AiNoteResult({
    required this.transcript,
    required this.summary,
  });

  final String transcript;
  final String summary;
}

abstract interface class NoteAiService {
  Future<bool> hasTranscriptionApiKey();
  Future<bool> hasSummaryApiKey();
  Future<void> saveTranscriptionApiKey(String apiKey);
  Future<void> saveSummaryApiKey(String apiKey);
  Future<AiNoteResult> transcribeAndSummarize(File audioFile);
}
