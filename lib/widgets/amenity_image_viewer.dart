import 'package:flutter/material.dart';

class AmenityImageViewer extends StatelessWidget {
  final String imageUrl;
  final String amenityName;
  final String? description;

  const AmenityImageViewer({
    super.key,
    required this.imageUrl,
    required this.amenityName,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      amenityName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Image
            if (imageUrl.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                      );
                    },
                  ),
                ),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: const Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
              ),
            
            // Description
            if (description != null && description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  description!,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
