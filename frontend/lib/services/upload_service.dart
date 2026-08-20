import 'dart:io';

import 'package:dio/dio.dart';

import '../core/network/api_client.dart';

/// Presigned S3 upload flow: ask the backend for a signed PUT URL, then PUT the file
/// bytes directly to S3 (never through our own server) using a plain Dio instance —
/// the presigned URL is already fully authenticated, it must NOT carry our API's
/// Authorization/JWT header or it'll be rejected by S3's signature check.
class UploadService {
  final ApiClient _client = ApiClient();
  final Dio _rawDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 120),
    receiveTimeout: const Duration(seconds: 60),
  ));

  Future<String> uploadFile({
    required String category, // 'kyc' | 'pod' | 'chat' | 'profile'
    required File file,
    required String contentType,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;

    final presignRes = await _client.post('/uploads/presign', data: {
      'category': category,
      'file_name': fileName,
      'content_type': contentType,
    });
    final uploadUrl = presignRes.data['data']['upload_url'] as String;
    final fileUrl = presignRes.data['data']['file_url'] as String;

    final bytes = await file.readAsBytes();
    await _rawDio.put(
      uploadUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {'Content-Type': contentType, 'Content-Length': bytes.length},
      ),
    );

    return fileUrl;
  }

  /// Same presign-then-PUT flow as [uploadFile], but takes raw bytes instead of a
  /// dart:io File — needed on Flutter Web, where File can't read the blob: URL an
  /// image/file picker returns.
  Future<String> uploadBytes({
    required String category,
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) async {
    final presignRes = await _client.post('/uploads/presign', data: {
      'category': category,
      'file_name': fileName,
      'content_type': contentType,
    });
    final uploadUrl = presignRes.data['data']['upload_url'] as String;
    final fileUrl = presignRes.data['data']['file_url'] as String;

    await _rawDio.put(
      uploadUrl,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {'Content-Type': contentType, 'Content-Length': bytes.length},
      ),
    );

    return fileUrl;
  }
}
