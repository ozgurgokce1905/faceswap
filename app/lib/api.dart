import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Sunucu ile konuşan tek sınıf. Adres ayarlardan okunur (ör. http://192.168.1.107:8765).
class Api {
  Api._();
  static final Api I = Api._();

  static const _keyBase = 'server_base';
  static const _keyWatermark = 'watermark';
  static const _keyPreset = 'preset';
  static const _keyToken = 'token';

  String baseUrl = 'http://192.168.1.107:8765';
  bool watermark = true;
  String defaultPreset = 'kaliteli';
  String token = '';

  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(minutes: 10)));

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString(_keyBase) ?? baseUrl;
    watermark = p.getBool(_keyWatermark) ?? true;
    defaultPreset = p.getString(_keyPreset) ?? 'kaliteli';
    token = p.getString(_keyToken) ?? '';
    _applyToken();
  }

  void _applyToken() {
    if (token.isNotEmpty) {
      _dio.options.headers['X-Token'] = token;
    } else {
      _dio.options.headers.remove('X-Token');
    }
  }

  Future<void> save({String? base, bool? wm, String? preset, String? tok}) async {
    final p = await SharedPreferences.getInstance();
    if (base != null) {
      var b = base.trim();
      if (!b.startsWith('http')) b = 'http://$b';
      b = b.replaceAll(RegExp(r'/+$'), '');
      if (b.startsWith('http://') && !RegExp(r':\d+$').hasMatch(b)) b = '$b:8765';
      baseUrl = b;
      await p.setString(_keyBase, b);
    }
    if (wm != null) {
      watermark = wm;
      await p.setBool(_keyWatermark, wm);
    }
    if (preset != null) {
      defaultPreset = preset;
      await p.setString(_keyPreset, preset);
    }
    if (tok != null) {
      token = tok.trim();
      await p.setString(_keyToken, token);
      _applyToken();
    }
  }

  String frameUrl(String videoId, int frame, {int maxSide = 720}) =>
      '$baseUrl/videos/$videoId/frame/$frame?max_side=$maxSide${token.isNotEmpty ? '&token=$token' : ''}';

  Future<ServerHealth> health() async {
    final r = await _dio.get('$baseUrl/health');
    return ServerHealth.fromJson(r.data as Map<String, dynamic>);
  }

  Future<VideoMeta> uploadVideo(File file, {void Function(double)? onProgress}) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last)});
    final r = await _dio.post('$baseUrl/videos', data: form,
        options: Options(sendTimeout: const Duration(minutes: 10)),
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) onProgress(sent / total);
        });
    return VideoMeta.fromJson(r.data as Map<String, dynamic>);
  }

  Future<FrameFaces> faces(String videoId, int frame) async {
    final r = await _dio.get('$baseUrl/videos/$videoId/faces/$frame', options: Options(receiveTimeout: const Duration(seconds: 60)));
    return FrameFaces.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<LibraryFace>> listFaces() async {
    final r = await _dio.get('$baseUrl/faces');
    return (r.data as List).map((e) => LibraryFace.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<LibraryFace> addFace(File image, {String name = ''}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(image.path, filename: image.uri.pathSegments.last),
      'name': name,
    });
    final r = await _dio.post('$baseUrl/faces', data: form);
    return LibraryFace.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> deleteFace(String id) => _dio.delete('$baseUrl/faces/$id');

  Future<Job> createJob({
    required String videoId,
    required int frameNumber,
    required int faceIndex,
    required List<String> faceIds,
    required String preset,
    int? trimStart,
    int? trimEnd,
    String mode = 'yuz',
  }) async {
    final r = await _dio.post('$baseUrl/jobs', data: {
      'mode': mode,
      'video_id': videoId,
      'frame_number': frameNumber,
      'face_index': faceIndex,
      'face_ids': faceIds,
      'preset': preset,
      'watermark': watermark,
      'trim_start': trimStart,
      'trim_end': trimEnd,
    });
    return Job.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Job> job(String id) async {
    final r = await _dio.get('$baseUrl/jobs/$id');
    return Job.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<Job>> jobs() async {
    final r = await _dio.get('$baseUrl/jobs');
    return (r.data as List).map((e) => Job.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> cancel(String id) => _dio.post('$baseUrl/jobs/$id/cancel');
  Future<void> wanSetup() => _dio.post('$baseUrl/wan/setup');
  Future<void> deleteJob(String id) => _dio.delete('$baseUrl/jobs/$id');

  Future<File> downloadResult(String jobId, String savePath, {void Function(double)? onProgress}) async {
    await _dio.download('$baseUrl/jobs/$jobId/result', savePath, onReceiveProgress: (got, total) {
      if (onProgress != null && total > 0) onProgress(got / total);
    });
    return File(savePath);
  }

  static bool baseUrlLooksLikeRunPod() => I.baseUrl.contains('proxy.runpod.net');

  /// Hata nesnesini kullanıcıya gösterilecek kısa Türkçe metne çevirir.
  static String err(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) return data['detail'].toString();
      if (e.response?.statusCode == 404 && baseUrlLooksLikeRunPod()) return 'Sunucu kapalı (RunPod pod açık değil).';
      if (e.response?.statusCode != null) return 'Sunucu hatası (HTTP ${e.response?.statusCode}).';
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.connectionError:
          return 'Sunucuya bağlanılamadı. Bilgisayarda sunucu açık mı, telefon aynı Wi-Fi’da mı?';
        case DioExceptionType.receiveTimeout:
          return 'Sunucu çok geç cevap verdi.';
        default:
          return e.message ?? e.toString();
      }
    }
    return e.toString();
  }
}
