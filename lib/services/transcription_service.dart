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

/// バックエンド経由の文字起こし（本番構成）。
///
/// 開発者のOpenAIキーはサーバー側（`backend/`）にのみ置き、アプリには
/// 埋め込まない。アプリは録音ファイルのバイト列をそのまま
/// `POST {baseUrl}/transcribe` に送り、`{text}` を受け取る。
class BackendTranscriptionService implements TranscriptionService {
  final String baseUrl;
  final String appSecret;
  final http.Client _client;

  BackendTranscriptionService({
    required this.baseUrl,
    this.appSecret = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<String> transcribe(String audioPath) async {
    if (baseUrl.trim().isEmpty) {
      throw TranscriptionException('音声入力は現在利用できません（サーバー未設定）');
    }
    final file = File(audioPath);
    if (!await file.exists()) {
      throw TranscriptionException('録音ファイルが見つかりません');
    }

    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final bytes = await file.readAsBytes();
    final response = await _client.post(
      Uri.parse('$base/transcribe'),
      headers: {
        'content-type': 'application/octet-stream',
        if (appSecret.isNotEmpty) 'X-App-Secret': appSecret,
      },
      body: bytes,
    );

    if (response.statusCode != 200) {
      throw TranscriptionException(
        'transcribe error ${response.statusCode}: ${response.body}',
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
