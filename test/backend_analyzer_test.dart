import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mindstock/models/models.dart';
import 'package:mindstock/services/diary_analyzer.dart';

void main() {
  group('BackendDiaryAnalyzer', () {
    test('/analyze に本文を送り events をパースする', () async {
      late String sentBody;
      final client = MockClient((req) async {
        expect(req.url.path, endsWith('/analyze'));
        sentBody = req.body;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'events': [
                {
                  'name': '合格',
                  'kind': 'milestone',
                  'isPositive': true,
                  'change': 107.3,
                },
              ],
            }),
          ),
          200,
        );
      });

      final analyzer = BackendDiaryAnalyzer(
        baseUrl: 'https://example.com',
        client: client,
      );
      final events = await analyzer.analyze('合格した', const []);

      // 送信ボタン本文が含まれている
      expect(sentBody, contains('合格した'));
      // change の絶対値が weight になる
      expect(events, hasLength(1));
      expect(events.first.name, '合格');
      expect(events.first.kind, EventKind.milestone);
      expect(events.first.weight, 107.3);
    });

    test('末尾スラッシュがあっても /analyze を二重にしない', () async {
      Uri? calledUri;
      final client = MockClient((req) async {
        calledUri = req.url;
        return http.Response('{"events":[]}', 200);
      });
      final analyzer = BackendDiaryAnalyzer(
        baseUrl: 'https://example.com/',
        client: client,
      );
      await analyzer.analyze('x', const []);
      expect(calledUri!.path, '/analyze');
    });

    test('非200は AnalyzerException を投げる', () async {
      final client = MockClient((_) async => http.Response('err', 500));
      final analyzer = BackendDiaryAnalyzer(
        baseUrl: 'https://example.com',
        client: client,
      );
      expect(
        () => analyzer.analyze('x', const []),
        throwsA(isA<AnalyzerException>()),
      );
    });
  });
}
