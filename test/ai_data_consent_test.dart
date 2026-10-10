import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindstock/models/models.dart';
import 'package:mindstock/providers.dart';
import 'package:mindstock/services/database_service.dart';
import 'package:mindstock/services/diary_analyzer.dart';
import 'package:mindstock/widgets/ai_data_consent_dialog.dart';

class _MemoryDatabase extends DatabaseService {
  final entries = <String, DiaryEntry>{};

  @override
  Future<Map<String, DiaryEntry>> loadAll() async => Map.of(entries);

  @override
  Future<void> upsert(DiaryEntry entry) async => entries[entry.date] = entry;
}

class _RemoteAnalyzer implements DiaryAnalyzer {
  int requests = 0;
  bool fail = false;

  @override
  Future<List<LifeEvent>> analyze(
    String text,
    List<DiaryEntry> recentEntries,
  ) async {
    requests++;
    if (fail) throw StateError('Offline');
    return [];
  }
}

void main() {
  for (final permission in [false, true]) {
    test('cloud requests require explicit permission: $permission', () async {
      final db = _MemoryDatabase();
      final remote = _RemoteAnalyzer();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          analyzerProvider.overrideWithValue(remote),
        ],
      );
      addTearDown(container.dispose);
      await container.read(entriesProvider.future);
      final charged = await container
          .read(entriesProvider.notifier)
          .submitDiary(
            date: DateTime(2026, 10, 10),
            text: '今日は散歩した',
            allowCloudAnalysis: permission,
          );
      expect(remote.requests, permission ? 1 : 0);
      expect(charged, permission);
      expect(db.entries['2026-10-10']?.text, '今日は散歩した');
    });
  }

  test('cloud failure keeps the diary without consuming AI points', () async {
    final db = _MemoryDatabase();
    final remote = _RemoteAnalyzer()..fail = true;
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        analyzerProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);
    await container.read(entriesProvider.future);
    final charged = await container
        .read(entriesProvider.notifier)
        .submitDiary(
          date: DateTime(2026, 10, 10),
          text: '今日は散歩した',
          allowCloudAnalysis: true,
        );
    expect(charged, isFalse);
    expect(db.entries['2026-10-10']?.text, '今日は散歩した');
  });

  for (final voice in [false, true]) {
    testWidgets('data disclosure can be declined: voice=$voice', (
      tester,
    ) async {
      AiDataChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAiDataConsent(context, voice: voice);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Allow sharing with OpenAI?'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text(voice ? 'Cancel' : 'Save only on device'));
      await tester.pumpAndSettle();
      expect(result, voice ? AiDataChoice.cancel : AiDataChoice.local);
    });
  }
}
