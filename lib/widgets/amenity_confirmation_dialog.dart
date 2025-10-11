import 'package:flutter/material.dart';

class AmenityConfirmationDialog extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const AmenityConfirmationDialog({
    Key? key,
    required this.onConfirm,
    required this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Image'),
      content: const Text(
        'Do you want to upload an image for this amenity?',
        style: TextStyle(fontSize: 16),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text(
            'No',
            style: TextStyle(color: Colors.red),
          ),
        ),
        ElevatedButton(
          onPressed: onConfirm,
          child: const Text('Yes'),
        ),
      ],
    );
  }
}
