import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 音声ファイルを文字に起こすインターフェース。
abstract interface class TranscriptionService {
  /// [audioPath] の音声ファイルを日本語のテキストに変換する。
  Future<String> transcribe(String audioPath);
}

/// OpenAI Whisper API (`whisper-1`) による音声文字起こし。
///
/// 日記入力画面のマイクボタンから、録音した音声をここに渡して
/// 文字起こし結果を本文へ挿入する（仕様書 §3 の「しっかり書く」を
/// 音声でも成立させる — 話すだけで日記が書ける導線）。
class WhisperTranscriptionService implements TranscriptionService {
  static const _endpoint = 'https://api.openai.com/v1/audio/transcriptions';

  final String apiKey;
  final http.Client _client;

  WhisperTranscriptionService({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<String> transcribe(String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw TranscriptionException('録音ファイルが見つかりません');
    }

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = 'whisper-1'
      ..fields['language'] = 'ja'
      ..files.add(await http.MultipartFile.fromPath('file', audioPath));

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw TranscriptionException(
        'Whisper API error ${response.statusCode}: ${response.body}',
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    return (body['text'] as String? ?? '').trim();
  }
}

class TranscriptionException implements Exception {
  final String message;
  TranscriptionException(this.message);
  @override
  String toString() => message;
}
