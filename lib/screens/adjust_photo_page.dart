import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/avatar_service.dart';
import '../widgets/glass.dart';

/// Adjust-photo screen (built-ins only): circular preview with
/// pinch-zoom, rotate button, Use photo / Retake.
class AdjustPhotoPage extends StatefulWidget {
  final XFile initialFile;
  const AdjustPhotoPage({super.key, required this.initialFile});

  @override
  State<AdjustPhotoPage> createState() => _AdjustState();
}

class _AdjustState extends State<AdjustPhotoPage> {
  late XFile _file;
  late Future<Uint8List> _imageBytes;
  int _v = 0;
  bool _rot = false;

  @override
  void initState() {
    super.initState();
    _file = widget.initialFile;
    _imageBytes = _file.readAsBytes();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _rotate() async {
    if (_rot) return;
    setState(() => _rot = true);
    try {
      final r = await AvatarService.rotate90(_file);
      if (!mounted) return;
      setState(() {
        _file = r;
        _imageBytes = r.readAsBytes();
        _v++;
      });
    } catch (e) {
      _msg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _rot = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ClipOval(
      child: Container(
        width: 240,
        height: 240,
        color: Colors.white.withValues(alpha: 0.15),
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: FutureBuilder<Uint8List>(
            future: _imageBytes,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 48,
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                );
              }
              return Image.memory(
                snapshot.data!,
                key: ValueKey(_v),
                width: 240,
                height: 240,
                fit: BoxFit.cover,
              );
            },
          ),
        ),
      ),
    );

    final retakeBtn = Expanded(
      child: OutlinedButton.icon(
        onPressed: _rot ? null : () => Navigator.of(context).pop(),
        icon: const Icon(Icons.refresh, color: Colors.white70),
        label: const Text('Retake', style: TextStyle(color: Colors.white70)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          minimumSize: const Size(0, 50),
        ),
      ),
    );

    final rotateBtn = Expanded(
      child: OutlinedButton.icon(
        onPressed: _rot ? null : _rotate,
        icon: _rot
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.rotate_right, color: Colors.white70),
        label: const Text('Rotate', style: TextStyle(color: Colors.white70)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          minimumSize: const Size(0, 50),
        ),
      ),
    );

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Pinch to zoom and check your photo.',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        preview,
        const SizedBox(height: 8),
        const Text(
          'The round area is how it will look.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            retakeBtn,
            const SizedBox(width: 8),
            rotateBtn,
          ],
        ),
        const SizedBox(height: 12),
        GlassButton(
          label: 'Use photo',
          onPressed: () => Navigator.of(context).pop(_file),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjust photo'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      extendBodyBehindAppBar: true,
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: GlassCard(child: body),
          ),
        ),
      ),
    );
  }
}
