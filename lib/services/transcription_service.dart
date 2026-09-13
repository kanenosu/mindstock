import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 音声ファイルを文字に起こすインターフェース。
abstract interface class TranscriptionService {
  /// [audioPath] の音声ファイルをテキストへ変換する。
  ///
  /// [language] は Whisper が理解できる短縮言語コードを受け取る（例: `ja`, `en`）。
  /// 空なら実装側で既定値が使われる。
  Future<String> transcribe(String audioPath, {String? language});
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
  Future<String> transcribe(String audioPath, {String? language}) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw TranscriptionException('録音ファイルが見つかりません');
    }
    final safeLanguage = language?.trim();

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint))
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..fields['model'] = 'whisper-1'
      ..fields['language'] = (safeLanguage == null || safeLanguage.isEmpty)
          ? 'ja'
          : safeLanguage
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
  Future<String> transcribe(String audioPath, {String? language}) async {
    if (baseUrl.trim().isEmpty) {
      throw TranscriptionException('音声入力は現在利用できません（サーバー未設定）');
    }
    final file = File(audioPath);
    if (!await file.exists()) {
      throw TranscriptionException('録音ファイルが見つかりません');
    }

    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final safeLanguage = language?.trim();
    final bytes = await file.readAsBytes();
    final response = await _client.post(
      _transcribeEndpoint(base, language: safeLanguage),
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

  Uri _transcribeEndpoint(String baseUrl, {String? language}) {
    final base = Uri.parse(baseUrl);
    final cleanPath = base.path.replaceAll(RegExp(r'/+$'), '');
    final path = cleanPath.isEmpty ? '/transcribe' : '$cleanPath/transcribe';
    final nextQuery = Map<String, String>.from(base.queryParameters);
    if (language != null && language.isNotEmpty) {
      nextQuery['language'] = language;
    }
    return base.replace(
      path: path,
      queryParameters: nextQuery.isEmpty ? null : nextQuery,
    );
  }
}

class TranscriptionException implements Exception {
  final String message;
  TranscriptionException(this.message);
  @override
  String toString() => message;
}
