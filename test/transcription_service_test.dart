import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:mindstock/services/transcription_service.dart';

void main() {
  group('WhisperTranscriptionService', () {
    late File audio;

    setUp(() async {
      // 実ファイルの存在チェックを通すためのダミー音声ファイル
      audio = File('${Directory.systemTemp.path}/mindstock_test_audio.m4a');
      await audio.writeAsBytes([0, 1, 2, 3]);
    });

    tearDown(() async {
      if (await audio.exists()) await audio.delete();
    });

    test('200応答の text を trim して返す', () async {
      final client = MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer test-key');
        return http.Response(
          jsonEncode({'text': '  今日は良い一日だった  '}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = WhisperTranscriptionService(
        apiKey: 'test-key',
        client: client,
      );
      final result = await service.transcribe(audio.path);
      expect(result, '今日は良い一日だった');
    });

    test('非200応答は TranscriptionException を投げる', () async {
      final client = MockClient(
        (req) async => http.Response('unauthorized', 401),
      );
      final service = WhisperTranscriptionService(
        apiKey: 'bad-key',
        client: client,
      );
      expect(
        () => service.transcribe(audio.path),
        throwsA(isA<TranscriptionException>()),
      );
    });

    test('存在しないファイルは TranscriptionException を投げる', () async {
      final service = WhisperTranscriptionService(
        apiKey: 'test-key',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => service.transcribe('/no/such/file.m4a'),
        throwsA(isA<TranscriptionException>()),
      );
    });
  });

  group('BackendTranscriptionService', () {
    late File audio;

    setUp(() async {
      audio = File('${Directory.systemTemp.path}/mindstock_test_audio2.m4a');
      await audio.writeAsBytes([0, 1, 2, 3]);
    });

    tearDown(() async {
      if (await audio.exists()) await audio.delete();
    });

    test('/transcribe に送り、text を trim して返す（末尾スラッシュも吸収）', () async {
      final client = MockClient((req) async {
        expect(req.url.path, endsWith('/transcribe'));
        expect(req.headers['X-App-Secret'], 'sekret');
        expect(req.bodyBytes, [0, 1, 2, 3]);
        return http.Response(
          jsonEncode({'text': '  今日は良い一日だった  '}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = BackendTranscriptionService(
        baseUrl: 'https://api.example.com/',
        appSecret: 'sekret',
        client: client,
      );
      expect(await service.transcribe(audio.path), '今日は良い一日だった');
    });

    test('baseUrl 未設定は TranscriptionException を投げる', () async {
      final service = BackendTranscriptionService(
        baseUrl: '',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => service.transcribe(audio.path),
        throwsA(isA<TranscriptionException>()),
      );
    });

    test('非200応答は TranscriptionException を投げる', () async {
      final service = BackendTranscriptionService(
        baseUrl: 'https://api.example.com',
        client: MockClient((_) async => http.Response('upstream error', 502)),
      );
      expect(
        () => service.transcribe(audio.path),
        throwsA(isA<TranscriptionException>()),
      );
    });
  });
}
