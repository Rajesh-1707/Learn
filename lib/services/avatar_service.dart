import 'dart:io';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:image/image.dart' as imglib;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

/// Picks, validates, uploads avatar images to Cloudinary (unsigned),
/// and stores only the secure URL in profiles.avatar_url.
class AvatarService {
  final ImagePicker _picker;
  final SupabaseClient _client;

  AvatarService({ImagePicker? picker, SupabaseClient? client})
      : _picker = picker ?? ImagePicker(),
        _client = client ?? Supabase.instance.client;

  static const int maxBytes = 5 * 1024 * 1024;
  static const List<String> allowedExts = [
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  Future<File?> pickImage(ImageSource source) async {
    final XFile? x = await _picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (x == null) return null;
    final File file = File(x.path);
    _validate(file);
    return file;
  }

  /// Rotates the image 90° clockwise (used by the Adjust screen).
  /// Returns a new temp file; never modifies the original.
  static Future<File> rotate90(File file) async {
    final bytes = await file.readAsBytes();
    final decoded = imglib.decodeImage(bytes);
    if (decoded == null) {
      throw Exception(
          'Could not read that photo. Please choose a JPG, PNG or WEBP photo.');
    }
    final rotated = imglib.copyRotate(decoded, angle: 90);
    final out = imglib.encodeJpg(rotated, quality: 85);
    final dir = Directory.systemTemp;
    final outFile = File(
        '${dir.path}/avatar_rot_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await outFile.writeAsBytes(out, flush: true);
    _validateStatic(outFile);
    return outFile;
  }

  /// Shared validation used by the widget before uploading.
  static void validateFile(File file) => _validateStatic(file);

  static void _validateStatic(File file) {
    final ext = file.path.split('.').last.toLowerCase();
    if (!allowedExts.contains(ext)) {
      throw Exception(
          'That file is not a supported image. Please choose a JPG, PNG or WEBP photo.');
    }
    final size = file.lengthSync();
    if (size > maxBytes) {
      throw Exception(
          'That photo is too large (over 5 MB). Please choose a smaller one.');
    }
  }

  void _validate(File file) => _validateStatic(file);

  Future<String> uploadAvatar(File file) async {
    _validate(file);
    // Direct unsigned upload (no cloudinary_public: it converts
    // Cloudinary 401s into a bare DioException with no message).
    final url =
        'https://api.cloudinary.com/v1_1/${AppConfig.cloudinaryCloudName}/image/upload';
    final dio = dio_pkg.Dio();
    try {
      final res = await dio.post(
        url,
        data: dio_pkg.FormData.fromMap({
          'upload_preset': AppConfig.cloudinaryUploadPreset,
          'folder': 'avatars',
          'file': await dio_pkg.MultipartFile.fromFile(file.path),
        }),
      );
      final data = res.data;
      final secureUrl =
          data is Map ? '${data['secure_url'] ?? ''}'.trim() : '';
      if (secureUrl.isEmpty) {
        throw Exception('Upload failed: empty response from Cloudinary.');
      }
      return secureUrl;
    } on dio_pkg.DioException catch (e) {
      throw Exception(_dioMessage(e));
    }
  }

  /// Turns a Cloudinary 4xx into a human-readable message.
  static String _dioMessage(dio_pkg.DioException e) {
    final data = e.response?.data;
    String detail = '';
    if (data is Map && data['error'] is Map) {
      detail = '${data['error']['message'] ?? ''}'.trim();
    } else if (data != null) {
      detail = '$data'.trim();
      if (detail.length > 300) detail = detail.substring(0, 300);
    }
    final code = e.response?.statusCode;
    final low = detail.toLowerCase();
    if (low.contains('unknown api key') || low.contains('unknown cloud')) {
      return 'Cloudinary rejected the cloud name "${AppConfig.cloudinaryCloudName}". Copy the exact Cloud name from Cloudinary Console → Settings → Account (it is not the preset name).';
    }
    if (low.contains('preset') ||
        low.contains('unsigned') ||
        low.contains('whitelisted')) {
      return 'Preset "speakearn_avatars" error: ${detail.isEmpty ? "must exist, be Unsigned, and allow the avatars folder and jpg/png/webp" : detail}';
    }
    return 'Upload failed${code != null ? " ($code)" : ""}${detail.isNotEmpty ? ": $detail" : ". Check internet and try again."}';
  }

  Future<void> saveAvatarUrl(String? url) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Not signed in. Please log in again.');
    }
    await _client.from('profiles').update(
      {'avatar_url': url},
    ).eq('id', user.id);
  }

  /// Convenience: validate -> upload -> save, returns the new URL.
  Future<String> uploadAndSave(File file) async {
    final url = await uploadAvatar(file);
    await saveAvatarUrl(url);
    return url;
  }
}
