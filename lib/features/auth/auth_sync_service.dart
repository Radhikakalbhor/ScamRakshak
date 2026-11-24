import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../dashboard/detection_history.dart';
import '../lessons/lesson_models.dart';
import '../quiz/literacy_score.dart';
import '../report/report_data.dart';
import 'auth_api.dart';
import 'auth_models.dart';

/// Two-way synchronization service for user detection history, quiz, lessons, and reports.
///
/// Principles:
/// 1. Merges remote data with local data (never overwrites local data blindly).
/// 2. Privacy-first: Detection history syncs metadata only (verdict, score, category, ts);
///    never stores or syncs raw message text or call audio.
/// 3. Digital Financial Literacy (DFL) score is recomputed on device; never stored.
/// 4. Flushes offline queues when backend is reachable.
class AuthSyncService {
  final AuthApi _authApi;
  final ApiClient _apiClient;

  AuthSyncService({
    AuthApi? authApi,
    ApiClient? apiClient,
  })  : _authApi = authApi ?? AuthApi(),
        _apiClient = apiClient ?? ApiClient();

  /// Performs full two-way sync on sign-in or explicit sync trigger.
  Future<SyncDataPayload> syncAll({required String idToken}) async {
    // 1. Flush any queued reports first if backend is reachable
    try {
      if (await _apiClient.isReachable()) {
        await ReportQueue.flush(_apiClient);
      }
    } catch (_) {}

    // 2. Build local sync snapshot
    final localSnapshot = await buildLocalSnapshot();

    // 3. Push local changes and receive merged remote state
    final mergedState = await _authApi.pushSync(
      payload: localSnapshot,
      idToken: idToken,
    );

    // 4. Merge server's merged state back into local stores
    await applyRemoteState(mergedState);

    return mergedState;
  }

  /// Builds a snapshot of current local data to push to server.
  Future<SyncDataPayload> buildLocalSnapshot() async {
    // 1. Detection history
    final history = DetectionHistory();
    final localRecords = await history.load();
    final detectionItems = localRecords.map((r) {
      return DetectionHistorySyncItem(
        kind: r.kind,
        verdict: r.verdict,
        score: r.score ?? 0.0,
        category: r.category,
        ts: r.time.toUtc().toIso8601String(),
      );
    }).toList();

    // 2. Quiz progress
    final prefs = await SharedPreferences.getInstance();
    final rawQuiz = prefs.getString(LiteracyStore.key);
    final quizItems = <QuizProgressSyncItem>[];
    if (rawQuiz != null && rawQuiz.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawQuiz) as Map<String, dynamic>;
        final nowIso = DateTime.now().toUtc().toIso8601String();
        for (final entry in decoded.entries) {
          if (entry.value is List && (entry.value as List).length == 2) {
            final list = entry.value as List;
            quizItems.add(
              QuizProgressSyncItem(
                topic: entry.key,
                attempts: 1,
                correct: (list[0] as num).toInt(),
                total: (list[1] as num).toInt(),
                updatedAt: nowIso,
              ),
            );
          }
        }
      } catch (_) {}
    }

    // 3. Lesson progress
    final completedLessons = await LessonProgress.completed();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final lessonItems = completedLessons.map((id) {
      return LessonProgressSyncItem(
        lessonId: id,
        completedAt: nowIso,
      );
    }).toList();

    // 4. User reports
    final userReportItems = <UserReportSyncItem>[];
    final rawUserReports = prefs.getString('user_synced_reports_v1');
    if (rawUserReports != null && rawUserReports.isNotEmpty) {
      try {
        final list = jsonDecode(rawUserReports) as List;
        for (final item in list) {
          userReportItems.add(UserReportSyncItem.fromJson(Map<String, dynamic>.from(item as Map)));
        }
      } catch (_) {}
    }

    return SyncDataPayload(
      detectionHistory: detectionItems,
      quizProgress: quizItems,
      lessonProgress: lessonItems,
      userReports: userReportItems,
    );
  }

  /// Merges remote sync payload back into local stores.
  Future<void> applyRemoteState(SyncDataPayload remote) async {
    // 1. Detection History: Union merge
    final history = DetectionHistory();
    final currentLocal = await history.load();
    final existingKeys = {
      for (final r in currentLocal)
        '${r.kind}_${r.category}_${r.time.toUtc().toIso8601String()}'
    };

    for (final item in remote.detectionHistory) {
      final key = '${item.kind}_${item.category}_${item.ts}';
      if (!existingKeys.contains(key)) {
        final parsedTime = DateTime.tryParse(item.ts) ?? DateTime.now();
        final kind = (item.kind == 'call') ? 'call' : 'message';
        await history.add(
          DetectionRecord(
            kind: kind,
            verdict: item.verdict,
            category: item.category,
            score: item.score > 0 ? item.score : null,
            time: parsedTime,
          ),
        );
        existingKeys.add(key);
      }
    }

    // 2. Quiz Progress: merge into LiteracyStore
    final prefs = await SharedPreferences.getInstance();
    final rawQuiz = prefs.getString(LiteracyStore.key);
    final quizMap = <String, List<int>>{};
    if (rawQuiz != null && rawQuiz.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawQuiz) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          if (entry.value is List && (entry.value as List).length == 2) {
            quizMap[entry.key] = [
              ((entry.value as List)[0] as num).toInt(),
              ((entry.value as List)[1] as num).toInt(),
            ];
          }
        }
      } catch (_) {}
    }

    var quizChanged = false;
    for (final item in remote.quizProgress) {
      if (!quizMap.containsKey(item.topic)) {
        quizMap[item.topic] = [item.correct, item.total];
        quizChanged = true;
      }
    }
    if (quizChanged) {
      await prefs.setString(LiteracyStore.key, jsonEncode(quizMap));
    }

    // 3. Lesson Progress: mark done
    for (final item in remote.lessonProgress) {
      await LessonProgress.markDone(item.lessonId);
    }

    // 4. Save synced user reports
    await prefs.setString(
      'user_synced_reports_v1',
      jsonEncode(remote.userReports.map((e) => e.toJson()).toList()),
    );

    // Trigger local DFL score and progress listeners
    learningProgressChanged.value++;
  }
}
