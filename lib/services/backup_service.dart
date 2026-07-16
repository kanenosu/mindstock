import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Googleログイン + Google Drive（アプリ専用領域）へのバックアップ。
///
/// appDataFolder はこのアプリからしか見えない領域なので、
/// ユーザーのDriveを汚さずに日記データを丸ごと退避できる。
/// 機種変更やアンインストール後の復元に使う。
class BackupService {
  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _fileName = 'mindstock_backup.json';
  static const _driveFiles = 'https://www.googleapis.com/drive/v3/files';
  static const _driveUpload =
      'https://www.googleapis.com/upload/drive/v3/files';

  final GoogleSignIn _google = GoogleSignIn(scopes: const [_scope]);
  final http.Client _client;

  /// 認証ヘッダの供給元（テストで差し替え可能にするための注入点）。
  /// null の場合は Google ログイン済みアカウントの authHeaders を使う。
  final Future<Map<String, String>> Function()? _headerProvider;

  GoogleSignInAccount? _account;

  BackupService({
    http.Client? client,
    Future<Map<String, String>> Function()? headerProvider,
  }) : _client = client ?? http.Client(),
       _headerProvider = headerProvider;

  GoogleSignInAccount? get account => _account;

  /// 起動時などに前回のログインを復元する。
  /// 「silently」という名の通り、失敗しても例外は投げない
  /// （前回ログインが無い/iOS側のOAuthクライアント未設定など、
  /// 理由を問わずアプリを落とさず null を返すだけにする）。
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      _account = await _google.signInSilently();
    } catch (_) {
      _account = null;
    }
    return _account;
  }

  Future<GoogleSignInAccount?> signIn() async {
    try {
      _account = await _google.signIn();
    } on PlatformException catch (e) {
      throw BackupException(
        'Googleログインに失敗しました。iOS側のOAuth設定が未完了の可能性があります '
        '(${e.code})',
      );
    }
    return _account;
  }

  Future<void> signOut() async {
    await _google.signOut();
    _account = null;
  }

  Future<Map<String, String>> _headers() async {
    if (_headerProvider != null) return _headerProvider();
    final account = _account ?? await signIn();
    if (account == null) {
      throw BackupException('Googleログインが必要です');
    }
    return account.authHeaders;
  }

  Future<String?> _findFileId(Map<String, String> headers) async {
    final uri = Uri.parse(
      '$_driveFiles?spaces=appDataFolder'
      '&q=${Uri.encodeQueryComponent("name='$_fileName'")}'
      '&fields=files(id)',
    );
    final res = await _client.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw BackupException('Drive照会に失敗しました (${res.statusCode})');
    }
    final files = (jsonDecode(res.body)['files'] as List?) ?? const [];
    if (files.isEmpty) return null;
    return files.first['id'] as String?;
  }

  /// 全エントリーをJSONにしてDriveへ保存する（既存バックアップは上書き）。
  Future<void> backup(Iterable<DiaryEntry> entries) async {
    final headers = await _headers();
    final data = jsonEncode([for (final e in entries) e.toDbMap()]);
    final fileId = await _findFileId(headers);

    final http.Response res;
    if (fileId == null) {
      // 新規作成: multipart（メタデータ + 本体）
      const boundary = 'mindstock_backup_boundary';
      final body =
          '--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '${jsonEncode({
            'name': _fileName,
            'parents': ['appDataFolder'],
          })}\r\n'
          '--$boundary\r\n'
          'Content-Type: application/json\r\n\r\n'
          '$data\r\n'
          '--$boundary--';
      res = await _client.post(
        Uri.parse('$_driveUpload?uploadType=multipart'),
        headers: {
          ...headers,
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body,
      );
    } else {
      // 既存を上書き
      res = await _client.patch(
        Uri.parse('$_driveUpload/$fileId?uploadType=media'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: data,
      );
    }
    if (res.statusCode != 200) {
      throw BackupException('バックアップに失敗しました (${res.statusCode})');
    }
  }

  /// Driveからバックアップを取得して復元用のエントリー一覧を返す。
  Future<List<DiaryEntry>> restore() async {
    final headers = await _headers();
    final fileId = await _findFileId(headers);
    if (fileId == null) {
      throw BackupException('バックアップが見つかりません。先にバックアップを作成してください');
    }
    final res = await _client.get(
      Uri.parse('$_driveFiles/$fileId?alt=media'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw BackupException('復元に失敗しました (${res.statusCode})');
    }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return [
      for (final row in list)
        DiaryEntry.fromDbMap(Map<String, dynamic>.from(row as Map)),
    ];
  }
}

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => message;
}
