// put this in the same file (after _ListScreenState) or in lib/widgets/zoomable_image.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ZoomableImage extends StatefulWidget {
  /// Provide either [imageUrl] or [imageBytes]. If both provided, [imageBytes] wins.
  final String? imageUrl;
  final Uint8List? imageBytes;

  const ZoomableImage({Key? key, this.imageUrl, this.imageBytes}) : super(key: key);

  @override
  _ZoomableImageState createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    setState(() {
      if (_zoomed) {
        _controller.value = Matrix4.identity();
        _zoomed = false;
      } else {
        // quick zoom-in on double tap
        _controller.value = Matrix4.identity()..scale(2.0);
        _zoomed = true;
      }
    });
  }

  Widget _buildImage() {
    // imageBytes takes precedence
    if (widget.imageBytes != null) {
      return Image.memory(widget.imageBytes!, fit: BoxFit.contain);
    }

    final url = widget.imageUrl;
    if (url == null || url.isEmpty) {
      return const Center(child: Icon(Icons.image_not_supported, size: 48));
    }

    // Handle data URI: data:image/png;base64,....
    if (url.startsWith('data:')) {
      try {
        final base64Part = url.split(',').last;
        final bytes = base64Decode(base64Part);
        return Image.memory(bytes, fit: BoxFit.contain);
      } catch (e) {
        return const Center(child: Icon(Icons.broken_image, size: 48));
      }
    }

    // Otherwise treat as network URL
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1)
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 48)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        panEnabled: true,
        scaleEnabled: true,
        minScale: 0.5,
        maxScale: 4.0,
        child: _buildImage(),
      ),
    );
  }
}
