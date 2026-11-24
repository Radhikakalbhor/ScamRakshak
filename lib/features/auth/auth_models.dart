// Models and state objects for User Authentication, Profiles, and Sync.

enum AuthStatus {
  unauthenticated,
  authenticating,
  authenticated,
  offlineAuthenticated,
  error,
}

class UserProfile {
  final String uid;
  final String phone;
  final String username;
  final String district;
  final String language;
  final String createdAt;
  final String updatedAt;
  final bool? isNewUser;

  const UserProfile({
    required this.uid,
    required this.phone,
    required this.username,
    required this.district,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
    this.isNewUser,
  });

  UserProfile copyWith({
    String? uid,
    String? phone,
    String? username,
    String? district,
    String? language,
    String? createdAt,
    String? updatedAt,
    bool? isNewUser,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      phone: phone ?? this.phone,
      username: username ?? this.username,
      district: district ?? this.district,
      language: language ?? this.language,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isNewUser: isNewUser ?? this.isNewUser,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: (json['uid'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      district: (json['district'] ?? 'unknown').toString(),
      language: (json['language'] ?? 'en').toString(),
      createdAt: (json['created_at'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
      updatedAt: (json['updated_at'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
      isNewUser: json['is_new_user'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'phone': phone,
    'username': username,
    'district': district,
    'language': language,
    'created_at': createdAt,
    'updated_at': updatedAt,
    if (isNewUser != null) 'is_new_user': isNewUser,
  };
}

class DetectionHistorySyncItem {
  final int? id;
  final String kind;
  final String verdict;
  final double score;
  final String category;
  final String ts;

  const DetectionHistorySyncItem({
    this.id,
    required this.kind,
    required this.verdict,
    required this.score,
    required this.category,
    required this.ts,
  });

  factory DetectionHistorySyncItem.fromJson(Map<String, dynamic> json) {
    return DetectionHistorySyncItem(
      id: json['id'] as int?,
      kind: (json['kind'] ?? 'message').toString(),
      verdict: (json['verdict'] ?? 'safe').toString(),
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      category: (json['category'] ?? '').toString(),
      ts: (json['ts'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'kind': kind,
    'verdict': verdict,
    'score': score,
    'category': category,
    'ts': ts,
  };
}

class QuizProgressSyncItem {
  final String topic;
  final int attempts;
  final int correct;
  final int total;
  final String updatedAt;

  const QuizProgressSyncItem({
    required this.topic,
    required this.attempts,
    required this.correct,
    required this.total,
    required this.updatedAt,
  });

  factory QuizProgressSyncItem.fromJson(Map<String, dynamic> json) {
    return QuizProgressSyncItem(
      topic: (json['topic'] ?? '').toString(),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 5,
      updatedAt: (json['updated_at'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'topic': topic,
    'attempts': attempts,
    'correct': correct,
    'total': total,
    'updated_at': updatedAt,
  };
}

class LessonProgressSyncItem {
  final String lessonId;
  final String completedAt;

  const LessonProgressSyncItem({
    required this.lessonId,
    required this.completedAt,
  });

  factory LessonProgressSyncItem.fromJson(Map<String, dynamic> json) {
    return LessonProgressSyncItem(
      lessonId: (json['lesson_id'] ?? '').toString(),
      completedAt: (json['completed_at'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'lesson_id': lessonId,
    'completed_at': completedAt,
  };
}

class UserReportSyncItem {
  final int? id;
  final String type;
  final String district;
  final String ts;

  const UserReportSyncItem({
    this.id,
    required this.type,
    required this.district,
    required this.ts,
  });

  factory UserReportSyncItem.fromJson(Map<String, dynamic> json) {
    return UserReportSyncItem(
      id: json['id'] as int?,
      type: (json['type'] ?? 'other').toString(),
      district: (json['district'] ?? 'unknown').toString(),
      ts: (json['ts'] ?? DateTime.now().toUtc().toIso8601String()).toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'type': type,
    'district': district,
    'ts': ts,
  };
}

class SyncDataPayload {
  final List<DetectionHistorySyncItem> detectionHistory;
  final List<QuizProgressSyncItem> quizProgress;
  final List<LessonProgressSyncItem> lessonProgress;
  final List<UserReportSyncItem> userReports;

  const SyncDataPayload({
    this.detectionHistory = const [],
    this.quizProgress = const [],
    this.lessonProgress = const [],
    this.userReports = const [],
  });

  factory SyncDataPayload.fromJson(Map<String, dynamic> json) {
    return SyncDataPayload(
      detectionHistory: ((json['detection_history'] as List?) ?? [])
          .map((e) => DetectionHistorySyncItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      quizProgress: ((json['quiz_progress'] as List?) ?? [])
          .map((e) => QuizProgressSyncItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      lessonProgress: ((json['lesson_progress'] as List?) ?? [])
          .map((e) => LessonProgressSyncItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      userReports: ((json['user_reports'] as List?) ?? [])
          .map((e) => UserReportSyncItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'detection_history': detectionHistory.map((e) => e.toJson()).toList(),
    'quiz_progress': quizProgress.map((e) => e.toJson()).toList(),
    'lesson_progress': lessonProgress.map((e) => e.toJson()).toList(),
    'user_reports': userReports.map((e) => e.toJson()).toList(),
  };
}

class AuthState {
  final AuthStatus status;
  final UserProfile? userProfile;
  final String? errorMessage;
  final bool isSynced;
  final bool isSyncing;

  const AuthState({
    required this.status,
    this.userProfile,
    this.errorMessage,
    this.isSynced = true,
    this.isSyncing = false,
  });

  factory AuthState.unauthenticated() => const AuthState(
    status: AuthStatus.unauthenticated,
  );

  factory AuthState.authenticating() => const AuthState(
    status: AuthStatus.authenticating,
  );

  factory AuthState.authenticated(UserProfile profile, {bool isSynced = true}) => AuthState(
    status: AuthStatus.authenticated,
    userProfile: profile,
    isSynced: isSynced,
  );

  factory AuthState.offlineAuthenticated(UserProfile profile) => AuthState(
    status: AuthStatus.offlineAuthenticated,
    userProfile: profile,
    isSynced: false,
  );

  factory AuthState.error(String message, {UserProfile? profile}) => AuthState(
    status: AuthStatus.error,
    userProfile: profile,
    errorMessage: message,
  );

  bool get isAuthenticated =>
      status == AuthStatus.authenticated || status == AuthStatus.offlineAuthenticated;

  bool get isOfflineAuthenticated => status == AuthStatus.offlineAuthenticated;

  AuthState copyWith({
    AuthStatus? status,
    UserProfile? userProfile,
    String? errorMessage,
    bool? isSynced,
    bool? isSyncing,
  }) {
    return AuthState(
      status: status ?? this.status,
      userProfile: userProfile ?? this.userProfile,
      errorMessage: errorMessage ?? this.errorMessage,
      isSynced: isSynced ?? this.isSynced,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}
