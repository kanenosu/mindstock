import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:mindstock/models/models.dart';
import 'package:mindstock/services/backup_service.dart';

/// テスト用の固定認証ヘッダ（本物のGoogleログインを介さない）。
Future<Map<String, String>> _fakeHeaders() async => {
  'Authorization': 'Bearer fake-token',
};

const _sampleEntry = DiaryEntry(
  date: '2026-07-16',
  text: '合格した',
  events: [
    LifeEvent(
      name: '合格',
      kind: EventKind.milestone,
      isPositive: true,
      weight: 107.3,
    ),
  ],
);

void main() {
  group('BackupService.backup', () {
    test('バックアップが無ければ multipart で新規作成する', () async {
      var createdWithMultipart = false;
      final client = MockClient((req) async {
        // 1) ファイルID照会 → 空
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          return http.Response(jsonEncode({'files': []}), 200);
        }
        // 2) 新規作成（アップロード）
        if (req.method == 'POST' && req.url.path == '/upload/drive/v3/files') {
          expect(req.headers['Content-Type'], contains('multipart/related'));
          expect(req.body, contains('合格'));
          createdWithMultipart = true;
          return http.Response(jsonEncode({'id': 'new-id'}), 200);
        }
        return http.Response('unexpected', 500);
      });

      final service = BackupService(
        client: client,
        headerProvider: _fakeHeaders,
      );
      await service.backup([_sampleEntry]);
      expect(createdWithMultipart, isTrue);
    });

    test('既存バックアップがあれば PATCH で上書きする', () async {
      var patched = false;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'existing-id'},
              ],
            }),
            200,
          );
        }
        if (req.method == 'PATCH' &&
            req.url.path == '/upload/drive/v3/files/existing-id') {
          patched = true;
          return http.Response(jsonEncode({'id': 'existing-id'}), 200);
        }
        return http.Response('unexpected', 500);
      });

      final service = BackupService(
        client: client,
        headerProvider: _fakeHeaders,
      );
      await service.backup([_sampleEntry]);
      expect(patched, isTrue);
    });

    test('アップロード失敗時は BackupException を投げる', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(jsonEncode({'files': []}), 200);
        }
        return http.Response('server error', 500);
      });
      final service = BackupService(
        client: client,
        headerProvider: _fakeHeaders,
      );
      expect(
        () => service.backup([_sampleEntry]),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('BackupService.restore', () {
    test('バックアップ内容をエントリー一覧にパースする', () async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'existing-id'},
              ],
            }),
            200,
          );
        }
        // ファイル本体の取得（alt=media）。
        // 日本語を含むので utf8 バイトで返す（restore は bodyBytes を
        // utf8.decode するため）。
        if (req.method == 'GET' &&
            req.url.path == '/drive/v3/files/existing-id') {
          return http.Response.bytes(
            utf8.encode(jsonEncode([_sampleEntry.toDbMap()])),
            200,
          );
        }
        return http.Response('unexpected', 500);
      });

      final service = BackupService(
        client: client,
        headerProvider: _fakeHeaders,
      );
      final restored = await service.restore();
      expect(restored, hasLength(1));
      expect(restored.first.date, '2026-07-16');
      expect(restored.first.events.first.name, '合格');
    });

    test('バックアップが無ければ BackupException を投げる', () async {
      final client = MockClient((req) async {
        return http.Response(jsonEncode({'files': []}), 200);
      });
      final service = BackupService(
        client: client,
        headerProvider: _fakeHeaders,
      );
      expect(() => service.restore(), throwsA(isA<BackupException>()));
    });
  });
}
