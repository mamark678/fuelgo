import 'dart:convert';

import 'package:flutter/material.dart';

class Base64ImageViewer extends StatelessWidget {
  final String base64Image;
  final String title;
  final String? description;

  const Base64ImageViewer({
    Key? key,
    required this.base64Image,
    required this.title,
    this.description,
  }) : super(key: key);

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
                      title,
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
            if (base64Image.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  child: Image.memory(
                    base64Decode(base64Image),
                    fit: BoxFit.cover,
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
