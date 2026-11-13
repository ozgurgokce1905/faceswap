/// Sunucudan gelen veri modelleri.

class VideoMeta {
  final String id;
  final String name;
  final double fps;
  final int frameCount;
  final int width;
  final int height;
  final double duration;

  VideoMeta({
    required this.id,
    required this.name,
    required this.fps,
    required this.frameCount,
    required this.width,
    required this.height,
    required this.duration,
  });

  factory VideoMeta.fromJson(Map<String, dynamic> j) => VideoMeta(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        fps: (j['fps'] as num).toDouble(),
        frameCount: (j['frame_count'] as num).toInt(),
        width: (j['width'] as num).toInt(),
        height: (j['height'] as num).toInt(),
        duration: (j['duration'] as num).toDouble(),
      );
}

/// Karede bulunan bir yüz (kişi).
class DetectedFace {
  final int index;
  final List<double> bboxNorm; // x1 y1 x2 y2 (0..1)
  final double score;
  final String? gender;
  final String thumbB64;

  DetectedFace({
    required this.index,
    required this.bboxNorm,
    required this.score,
    this.gender,
    required this.thumbB64,
  });

  factory DetectedFace.fromJson(Map<String, dynamic> j) => DetectedFace(
        index: (j['index'] as num).toInt(),
        bboxNorm: (j['bbox_norm'] as List).map((e) => (e as num).toDouble()).toList(),
        score: (j['score'] as num).toDouble(),
        gender: j['gender'] as String?,
        thumbB64: (j['thumb'] ?? '') as String,
      );
}

class FrameFaces {
  final int frameNumber;
  final int width;
  final int height;
  final List<DetectedFace> faces;

  FrameFaces({required this.frameNumber, required this.width, required this.height, required this.faces});

  factory FrameFaces.fromJson(Map<String, dynamic> j) => FrameFaces(
        frameNumber: (j['frame_number'] as num).toInt(),
        width: (j['width'] as num).toInt(),
        height: (j['height'] as num).toInt(),
        faces: ((j['faces'] ?? []) as List).map((e) => DetectedFace.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Kütüphanedeki kaynak yüz.
class LibraryFace {
  final String id;
  final String name;
  final String thumbB64;

  LibraryFace({required this.id, required this.name, required this.thumbB64});

  factory LibraryFace.fromJson(Map<String, dynamic> j) => LibraryFace(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        thumbB64: (j['thumb'] ?? '') as String,
      );
}

class Job {
  final String id;
  final String status; // queued running done error cancelled
  final String stage;
  final double percent;
  final int? done;
  final int? total;
  final String? error;
  final String? videoId;
  final String? videoName;
  final String preset;
  final String mode;
  final int? etaSeconds;
  final int? elapsed;
  final double? created;

  Job({
    required this.id,
    required this.status,
    required this.stage,
    required this.percent,
    this.done,
    this.total,
    this.error,
    this.videoId,
    this.videoName,
    required this.preset,
    this.mode = 'yuz',
    this.etaSeconds,
    this.elapsed,
    this.created,
  });

  bool get isFinished => status == 'done' || status == 'error' || status == 'cancelled';

  factory Job.fromJson(Map<String, dynamic> j) => Job(
        id: j['id'] as String,
        status: (j['status'] ?? '') as String,
        stage: (j['stage'] ?? '') as String,
        percent: ((j['percent'] ?? 0) as num).toDouble(),
        done: (j['done'] as num?)?.toInt(),
        total: (j['total'] as num?)?.toInt(),
        error: j['error'] as String?,
        videoId: j['video_id'] as String?,
        videoName: j['video_name'] as String?,
        preset: (j['preset'] ?? 'kaliteli') as String,
        mode: (j['mode'] ?? 'yuz') as String,
        etaSeconds: (j['eta_seconds'] as num?)?.toInt(),
        elapsed: (j['elapsed'] as num?)?.toInt(),
        created: (j['created'] as num?)?.toDouble(),
      );
}

class ServerHealth {
  final String provider;
  final bool busy;
  final Map<String, String> presets;
  final Map<String, double> secondsPerFrame;
  final BodyStatus body;

  ServerHealth({required this.provider, required this.busy, required this.presets, required this.secondsPerFrame, required this.body});

  factory ServerHealth.fromJson(Map<String, dynamic> j) => ServerHealth(
        provider: (j['provider'] ?? '?') as String,
        busy: (j['busy'] ?? false) as bool,
        presets: ((j['presets'] ?? {}) as Map).map((k, v) => MapEntry(k as String, v as String)),
        secondsPerFrame: ((j['seconds_per_frame'] ?? {}) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        body: BodyStatus.fromJson((j['body'] ?? const {}) as Map),
      );
}

/// Tüm vücut modunun (Wan2.2 Animate) sunucudaki durumu.
class BodyStatus {
  final bool available; // sunucuda mümkün mü (CUDA)
  final String status; // none / installing / ready / error
  final String stage;
  final Map<String, double> secondsPerFrame;

  BodyStatus({required this.available, required this.status, required this.stage, required this.secondsPerFrame});

  bool get ready => status == 'ready';

  factory BodyStatus.fromJson(Map j) => BodyStatus(
        available: (j['available'] ?? false) as bool,
        status: (j['status'] ?? 'none').toString(),
        stage: (j['stage'] ?? '').toString(),
        secondsPerFrame: ((j['seconds_per_frame'] ?? {}) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      );
}
