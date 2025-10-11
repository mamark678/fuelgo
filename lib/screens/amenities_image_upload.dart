import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AmenitiesImageUpload extends StatefulWidget {
  final String stationId;

  const AmenitiesImageUpload({Key? key, required this.stationId}) : super(key: key);

  @override
  _AmenitiesImageUploadState createState() => _AmenitiesImageUploadState();
}

class _AmenitiesImageUploadState extends State<AmenitiesImageUpload> {
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _amenities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAmenities();
  }

  Future<void> _loadAmenities() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('gas_stations')
          .doc(widget.stationId)
          .get();
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _amenities = List<Map<String, dynamic>>.from(data['amenities'] ?? []);
      }
    } catch (e) {
      print('Error loading amenities: $e');
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      // Show preview dialog with the selected image
      bool? shouldUpload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Preview Image'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(
                bytes,
                height: 200,
                width: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              const Text('Is this the correct image you want to upload?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Upload'),
            ),
          ],
        ),
      );
      
      if (shouldUpload == true) {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Uploading image...'),
              ],
            ),
          ),
        );
        
        try {
          final newAmenity = {
            'name': 'Uploaded Amenity',
            'type': 'image',
            'image': base64Image,
            'imageUrl': '',
            'uploadedAt': Timestamp.now(),
            'description': 'Uploaded amenity image',
          };
          
          await FirebaseFirestore.instance
              .collection('gas_stations')
              .doc(widget.stationId)
              .update({
                'amenities': FieldValue.arrayUnion([newAmenity])
              });
          
          Navigator.pop(context); // Close loading dialog
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image uploaded successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          
          _loadAmenities();
        } catch (e) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickImageWithName() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final nameController = TextEditingController();
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add Amenity with Preview'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.memory(
                  bytes,
                  height: 150,
                  width: 150,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'Enter amenity name',
                    labelText: 'Amenity Name',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  Navigator.pop(context); // Close name dialog
                  
                  // Show loading indicator
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => const AlertDialog(
                      content: Row(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(width: 16),
                          Text('Uploading image...'),
                        ],
                      ),
                    ),
                  );
                  
                  try {
                    final newAmenity = {
                      'name': nameController.text,
                      'type': 'image',
                      'image': base64Image,
                      'uploadedAt': Timestamp.now(),
                      'description': 'Uploaded amenity image',
                    };
                    
                    await FirebaseFirestore.instance
                        .collection('gas_stations')
                        .doc(widget.stationId)
                        .update({
                          'amenities': FieldValue.arrayUnion([newAmenity])
                        });
                    
                    Navigator.pop(context); // Close loading dialog
                    
                    // Show success message
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Image uploaded successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    
                    _loadAmenities();
                  } catch (e) {
                    Navigator.pop(context); // Close loading dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Upload failed: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Upload'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amenities with Images'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _pickImage,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _amenities.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.image, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No amenities uploaded yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _pickImageWithName,
                        child: const Text('Upload First Image'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _amenities.length,
                  itemBuilder: (context, index) {
                    final amenity = _amenities[index];
                    
                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    amenity['name'] ?? 'Unknown',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () async {
                                    bool? shouldDelete = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Amenity'),
                                        content: Text(
                                          'Are you sure you want to delete "${amenity['name']}"?'
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                            ),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    
                                    if (shouldDelete == true) {
                                      await FirebaseFirestore.instance
                                          .collection('gas_stations')
                                          .doc(widget.stationId)
                                          .update({
                                            'amenities': FieldValue.arrayRemove([amenity])
                                          });
                                      _loadAmenities();
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (amenity['type'] == 'image' && amenity['image'] != null)
                              GestureDetector(
                                onTap: () {
                                  // Show full screen image
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => Scaffold(
                                        appBar: AppBar(
                                          title: Text(amenity['name'] ?? 'Image'),
                                        ),
                                        body: Center(
                                          child: InteractiveViewer(
                                            panEnabled: true,
                                            boundaryMargin: const EdgeInsets.all(20),
                                            minScale: 0.5,
                                            maxScale: 4,
                                            child: Image.memory(
                                              base64Decode(amenity['image']),
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  width: double.infinity,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.grey[200],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      base64Decode(amenity['image']),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.image_not_supported),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              'Uploaded: ${(amenity['uploadedAt'] as Timestamp?)?.toDate().toString().substring(0, 16) ?? 'Unknown'}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickImageWithName,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
