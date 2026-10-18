import 'package:flutter/foundation.dart';

/// App-wide configuration.
///
/// Fill in your Cloudinary cloud name and Agora app ID below.
/// Public app configuration.
class AppConfig {
  static const String cloudinaryCloudName = 'o8kq8ldb';
  static const String cloudinaryUploadPreset = 'speakearn_avatars';

  /// The web app and its API are deployed to the same Vercel origin.
  /// Keep the placeholder fallback for native builds until their API host is set.
  static String get apiBaseUrl => kIsWeb
      ? Uri.base.origin
      : 'https://YOUR-PROJECT.vercel.app';
}
