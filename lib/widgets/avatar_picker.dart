import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../screens/adjust_photo_page.dart';

class AvatarPicker extends StatefulWidget {
  final String? avatarUrl;
  final String fallbackName;
  final ValueChanged<String?> onChanged;
  final double radius;
  const AvatarPicker({
    super.key,
    required this.avatarUrl,
    required this.onChanged,
    this.fallbackName = '',
    this.radius = 48,
  });
  @override
  State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  final AvatarService _svc = AvatarService();
  bool _busy = false;

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _showUploading() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Uploading photo...'),
        duration: Duration(seconds: 30),
      ),
    );
  }

  void _hideUploading() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  String _friendly(Object e) {
    final raw = e.toString().replaceFirst('Exception: ', '');
    final low = raw.toLowerCase();
    if (low.contains('too large') ||
        low.contains('supported image') ||
        low.contains('upload failed') ||
        low.contains('cloud name') ||
        low.contains('cloudinary') ||
        low.contains('preset')) {
      return raw;
    }
    return AuthService.friendlyMessage(e);
  }

  Future<void> _pick(ImageSource src) async {
    if (_busy) return;
    Navigator.of(context).maybePop();
    XFile? file;
    try {
      file = await _svc.pickImage(src);
    } catch (e) {
      if (!mounted) return;
      _msg(_friendly(e));
      return;
    }
    if (file == null) return;
    if (!mounted) return;
    // Adjust step: preview / zoom / rotate, or retake.
    final XFile picked = file;
    final adjusted = await Navigator.of(context).push<XFile?>(
      MaterialPageRoute(
          builder: (_) => AdjustPhotoPage(initialFile: picked)),
    );
    if (adjusted == null) return;
    if (!mounted) return;
    setState(() => _busy = true);
    _showUploading();
    try {
      final url = await _svc.uploadAndSave(adjusted);
      if (!mounted) return;
      _hideUploading();
      widget.onChanged(url);
      _msg('Profile photo updated.');
    } catch (e) {
      if (!mounted) return;
      _hideUploading();
      _msg(_friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    Navigator.of(context).maybePop();
    if (widget.avatarUrl == null || widget.avatarUrl!.isEmpty) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await _svc.saveAvatarUrl(null);
      if (!mounted) return;
      widget.onChanged(null);
      _msg('Profile photo removed.');
    } catch (e) {
      if (!mounted) return;
      _msg(_friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sheet() {
    if (_busy) return;
    final hasPhoto =
        widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF3B2A6E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text('Take photo',
                  style: TextStyle(color: Colors.white)),
              onTap: () => _pick(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Choose from gallery',
                  style: TextStyle(color: Colors.white)),
              onTap: () => _pick(ImageSource.gallery),
            ),
            if (hasPhoto)
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.white),
                title: const Text('Remove photo',
                    style: TextStyle(color: Colors.white)),
                onTap: _remove,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = (widget.avatarUrl ?? '').trim();
    final size = widget.radius * 2;
    final nm = widget.fallbackName.trim();
    final ini = nm.isNotEmpty ? nm[0].toUpperCase() : '';
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
              ),
            ],
          ),
          child: ClipOval(
            child: url.isNotEmpty
                ? Image.network(
                    url,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        width: size,
                        height: size,
                        color: Colors.white.withValues(alpha: 0.2),
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (ctx, err, stack) => Container(
                      width: size,
                      height: size,
                      color: Colors.white.withValues(alpha: 0.2),
                      child: const Icon(Icons.person,
                          color: Colors.white, size: 40),
                    ),
                  )
                : Container(
                    width: size,
                    height: size,
                    color: Colors.white.withValues(alpha: 0.2),
                    child: ini.isNotEmpty
                        ? Center(
                            child: Text(
                              ini,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : const Icon(Icons.person,
                            color: Colors.white, size: 40),
                  ),
          ),
        ),
        if (_busy)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.45),
            ),
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: _busy ? null : _sheet,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _busy
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.white,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 16,
                color: Color(0xFF5B3BA8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
