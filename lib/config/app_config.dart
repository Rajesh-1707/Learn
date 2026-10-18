import 'package:flutter/foundation.dart';

/// App-wide configuration.
///
/// Fill in your Cloudinary cloud name and Agora app ID below.
/// Public app configuration.
class AppConfig {
  static const String cloudinaryCloudName = 'o8kq8ldb';
  static const String cloudinaryUploadPreset = 'speakearn_avatars';

  /// The web app and its API are deployed to the same Vercel origin.
  /// Native builds use the deployed API origin.
  static String get apiBaseUrl => kIsWeb
      ? Uri.base.origin
      : 'https://speakearn-api.vercel.app/flutter/index.html';
}
