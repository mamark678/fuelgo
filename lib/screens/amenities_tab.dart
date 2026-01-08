import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/amenity_confirmation_dialog.dart';

class AmenitiesTab extends StatefulWidget {
  final List<Map<String, dynamic>> assignedStations;

  const AmenitiesTab({super.key, required this.assignedStations});

  @override
  State<AmenitiesTab> createState() => _AmenitiesTabState();
}

class _AmenitiesTabState extends State<AmenitiesTab> {
  final List<String> _availableAmenities = [
    'Restroom',
    'Convenience Store',
    'Car Wash',
    'Air Pump',
    'ATM',
    'WiFi',
    'Parking',
    '24/7 Service',
    'Food Court',
    'Coffee Shop',
    'Mechanic Service',
    'Tire Repair',
    'Oil Change',
    'Car Accessories',
    'Lottery',
    'Propane Exchange',
    'Electric Vehicle Charging',
    'Diesel Exhaust Fluid (DEF)',
    'Truck Parking',
    'RV Dump Station',
  ];

  Map<String, List<dynamic>> _stationAmenities = {};
  Map<String, List<String>> _stationPhotos = {}; // Store base64 photos
  bool _isLoading = true;
  final ImagePicker _picker = ImagePicker();

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadAmenities();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _loadAmenities() async {
    if (_isDisposed) return;
    
    if (widget.assignedStations.isEmpty) {
      if (!_isDisposed) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      for (final station in widget.assignedStations) {
        if (_isDisposed) return;
        
        final stationId = station['id'];
        final doc = await FirebaseFirestore.instance.collection('gas_stations').doc(stationId).get();
        if (doc.exists && !_isDisposed) {
          final data = doc.data() as Map<String, dynamic>;
          final amenities = data['amenities'] ?? [];
          final photos = data['photos'] ?? [];
          if (!_isDisposed) {
            setState(() {
              _stationAmenities[stationId] = List<dynamic>.from(amenities);
              _stationPhotos[stationId] = List<String>.from(photos);
            });
          }
        } else if (!_isDisposed) {
          if (!_isDisposed) {
            setState(() {
              _stationAmenities[stationId] = [];
              _stationPhotos[stationId] = [];
            });
          }
        }
      }
    } catch (e) {
      print('Error loading amenities: $e');
    } finally {
      if (!_isDisposed) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshAmenities() async {
    if (_isDisposed) return;
    
    if (!_isDisposed) {
      setState(() {
        _isLoading = true;
      });
    }
    await _loadAmenities();
  }

  Future<void> _toggleAmenity(String stationId, String amenity) async {
  if (_isDisposed) return;

  try {
    final currentAmenities = List<dynamic>.from(_stationAmenities[stationId] ?? []);
    final index = currentAmenities.indexWhere((a) => a is String ? a == amenity : a['name'] == amenity);

    if (index != -1) {
      // Remove amenity
      currentAmenities.removeAt(index);
      await FirebaseFirestore.instance.collection('gas_stations').doc(stationId).update({
        'amenities': currentAmenities,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      if (!_isDisposed) {
        setState(() {
          _stationAmenities[stationId] = currentAmenities;
        });
      }
      if (!_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed $amenity'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } else {
      // Add the amenity first
      currentAmenities.add(amenity);
      await FirebaseFirestore.instance.collection('gas_stations').doc(stationId).update({
        'amenities': currentAmenities,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      if (!_isDisposed) {
        setState(() {
          _stationAmenities[stationId] = currentAmenities;
        });
      }
      if (!_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $amenity'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }

      // Show photo upload prompt
      final bool? shouldUpload = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AmenityConfirmationDialog(
            onConfirm: () => Navigator.of(context).pop(true),
            onCancel: () => Navigator.of(context).pop(false),
          );
        },
      );

      if (shouldUpload == false) return; // User clicked "No" in the confirmation dialog

      // Add the image
      await _uploadAmenityPhoto(stationId, amenity);
    }
  } catch (e) {
    print('Error toggling amenity: $e');
  }
}

  Future<void> _uploadAmenityPhoto(String stationId, String amenityName) async {
    try {
      // Show source selection dialog
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Select Image Source'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Camera'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ],
            ),
          );
        },
      );

      if (source == null) return;

      // Pick multiple images (at least 2)
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 800,
        maxHeight: 600,
        imageQuality: 80,
      );

      if (images.length < 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select at least 1 images'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Uploading images...'),
                ],
              ),
            );
          },
        );
      }

      // Convert images to base64
      final List<String> base64Images = [];
      for (final image in images) {
        final Uint8List imageBytes = await image.readAsBytes();
        final String base64String = base64Encode(imageBytes);
        base64Images.add(base64String);
      }

      // Create amenity with images
      final amenityWithImages = {
        'name': amenityName,
        'type': 'image',
        'images': base64Images, // This is correct - array of base64 strings
        'imageCount': base64Images.length, // Helpful for quick counts
        'createdAt': DateTime.now().millisecondsSinceEpoch, // Timestamp
        'lastUpdated': DateTime.now().millisecondsSinceEpoch, // For version tracking
      };

      // Update Firestore - replace text amenity with image amenity
      final currentAmenities = List<dynamic>.from(_stationAmenities[stationId] ?? []);
      final index = currentAmenities.indexWhere((a) => a is String ? a == amenityName : a['name'] == amenityName);

      if (index != -1) {
        currentAmenities[index] = amenityWithImages;
      } else {
        currentAmenities.add(amenityWithImages);
      }

      await FirebaseFirestore.instance.collection('gas_stations').doc(stationId).update({
        'amenities': currentAmenities,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      setState(() {
        _stationAmenities[stationId] = currentAmenities;
      });

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photos uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if open
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading photos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('Error uploading images: $e');
    }
  }

  Future<void> _pickAndUploadImage(String stationId) async {
    try {
      // Show confirmation dialog first
      final bool? shouldUpload = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AmenityConfirmationDialog(
            onConfirm: () => Navigator.of(context).pop(true),
            onCancel: () => Navigator.of(context).pop(false),
          );
        },
      );

      if (shouldUpload != true) return;

      // Show source selection dialog
      final ImageSource? source = await showDialog<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Select Image Source'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Camera'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ],
            ),
          );
        },
      );

      if (source == null) return;

      // Pick image
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 600,
        imageQuality: 80,
      );

      if (image == null) return;

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Uploading image...'),
                ],
              ),
            );
          },
        );
      }

      // Convert to base64
      final Uint8List imageBytes = await image.readAsBytes();
      final String base64String = base64Encode(imageBytes);

      // Update Firestore
      final currentPhotos = List<String>.from(_stationPhotos[stationId] ?? []);
      currentPhotos.add(base64String);

      await FirebaseFirestore.instance.collection('gas_stations').doc(stationId).update({
        'photos': currentPhotos,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update local state
      setState(() {
        _stationPhotos[stationId] = currentPhotos;
      });

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if open
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('Error uploading image: $e');
    }
  }

  Future<void> _deletePhoto(String stationId, int photoIndex) async {
    try {
      final currentPhotos = List<String>.from(_stationPhotos[stationId] ?? []);
      currentPhotos.removeAt(photoIndex);

      await FirebaseFirestore.instance.collection('gas_stations').doc(stationId).update({
        'photos': currentPhotos,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      setState(() {
        _stationPhotos[stationId] = currentPhotos;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo deleted successfully!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPhotoGallery(String stationId, List<String> photos) {
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No photos available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Station Photos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    itemBuilder: (context, index) {
                      final base64Photo = photos[index];
                      final imageBytes = base64Decode(base64Photo);
                      
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          children: [
                            Container(
                              width: 250,
                              height: 200,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                image: DecorationImage(
                                  image: MemoryImage(imageBytes),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _deletePhoto(stationId, index);
                              },
                              icon: const Icon(Icons.delete, color: Colors.white),
                              label: const Text('Delete'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddCustomAmenityDialog(String stationId) {
    final TextEditingController customAmenityController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Custom Amenity'),
          content: TextField(
            controller: customAmenityController,
            decoration: const InputDecoration(
              hintText: 'Enter amenity name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final customAmenity = customAmenityController.text.trim();
                if (customAmenity.isNotEmpty) {
                  Navigator.of(context).pop(); // Close the input dialog
                  
                  // Show photo upload confirmation
                  final bool? shouldUploadPhoto = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) {
                      return AmenityConfirmationDialog(
                        onConfirm: () => Navigator.of(context).pop(true),
                        onCancel: () => Navigator.of(context).pop(false),
                      );
                    },
                  );

                  if (shouldUploadPhoto == null) return; // User cancelled

                  // Add the custom amenity
                  final currentAmenities = List<dynamic>.from(_stationAmenities[stationId] ?? []);
                  currentAmenities.add(customAmenity);
                  
                  await FirebaseFirestore.instance.collection('gas_stations').doc(stationId).update({
                    'amenities': currentAmenities,
                    'lastUpdated': FieldValue.serverTimestamp(),
                  });
                  
                  setState(() {
                    _stationAmenities[stationId] = currentAmenities;
                  });

                  if (shouldUploadPhoto) {
                    // Upload photo for the custom amenity
                    await _uploadAmenityPhoto(stationId, customAmenity);
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added $customAmenity'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshAmenities,
        child: widget.assignedStations.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.storefront, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No Stations Assigned',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Contact admin to assign gas stations to your account.',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: widget.assignedStations.length,
                itemBuilder: (context, index) {
                  final station = widget.assignedStations[index];
                  final stationId = station['id'];
                  final stationName = station['stationName'] ?? station['name'] ?? 'Unknown Station';
                  final amenities = _stationAmenities[stationId] ?? [];
                  final photos = _stationPhotos[stationId] ?? [];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  stationName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${amenities.length} amenities',
                                  style: TextStyle(
                                    color: Colors.blue.shade800,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            station['address'] ?? 'Address not available',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 16),
                          
                          // Quick Actions
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _showAddCustomAmenityDialog(stationId),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Custom'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await FirebaseFirestore.instance.collection('gas_stations').doc(stationId).update({
                                      'amenities': [],
                                      'lastUpdated': FieldValue.serverTimestamp(),
                                    });
                                    setState(() {
                                      _stationAmenities[stationId] = [];
                                    });
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('All amenities cleared'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.clear_all),
                                  label: const Text('Clear All'),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Amenities Grid
                          const Text(
                            'Available Amenities:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: _availableAmenities.length,
                            itemBuilder: (context, amenityIndex) {
                              final amenity = _availableAmenities[amenityIndex];
                              final isSelected = amenities.any((a) {
                                if (a is String && amenity is String) {
                                  return a == amenity;
                                } else if (a is Map && amenity is String) {
                                  return a['name'] == amenity;
                                }
                                return false;
                              });
                              
                              return GestureDetector(
                                onTap: () => _toggleAmenity(stationId, amenity),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.blue.shade100
                                        : Colors.grey.shade100,
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.blue
                                          : Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        amenity,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isSelected
                                              ? Colors.blue.shade800
                                              : Colors.black87,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          
                          // Current Amenities Display
                          if (amenities.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Current Amenities:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: amenities.map((amenity) {
                              final amenityName = amenity is String ? amenity : amenity['name'] ?? 'Unknown';
                              final hasImages = amenity is Map && amenity['type'] == 'image' && ((amenity['images'] != null && (amenity['images'] as List).isNotEmpty) || amenity['image'] != null);
                              return GestureDetector(
                                onTap: hasImages ? () {
                                  final amenityData = amenities.firstWhere(
                                    (a) => (a is String ? a == amenityName : a['name'] == amenityName),
                                    orElse: () => null,
                                  );
                                  if (amenityData != null && amenityData is Map && amenityData['type'] == 'image') {
                                    final List<String> images = amenityData['images'] != null ? List<String>.from(amenityData['images']) : (amenityData['image'] != null ? [amenityData['image']] : []);
                                    if (images.isNotEmpty) {
                                      showDialog(
                                        context: context,
                                        builder: (context) => Dialog(
                                          child: Container(
                                            width: MediaQuery.of(context).size.width * 0.9,
                                            height: MediaQuery.of(context).size.height * 0.7,
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min, // ← CRITICAL
                                              children: [
                                                Text(
                                                  amenityName,
                                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                                ),
                                                const SizedBox(height: 16),
                                                // ← KEY FIX: Wrap PageView with Expanded
                                                Expanded(
                                                  child: PageView.builder(
                                                    itemCount: images.length,
                                                    itemBuilder: (context, index) {
                                                      return InteractiveViewer(
                                                        panEnabled: true,
                                                        boundaryMargin: const EdgeInsets.all(20),
                                                        minScale: 0.5,
                                                        maxScale: 4,
                                                        child: Image.memory(
                                                          base64Decode(images[index]),
                                                          fit: BoxFit.contain,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                if (images.length > 1)
                                                  Text(
                                                    'Swipe to view ${images.length} images',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                const SizedBox(height: 8),
                                                TextButton(
                                                  onPressed: () => Navigator.of(context).pop(),
                                                  child: const Text('Close'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                } : null,
                                child: Chip(
                                  label: Text(amenityName),
                                  avatar: CircleAvatar(
                                    backgroundColor: Colors.transparent,
                                    child: hasImages 
                                      ? Stack(
                                          children: [
                                            Icon(_getAmenityIcon(amenityName), color: Colors.blue, size: 18),
                                            if (amenity['images'] != null && (amenity['images'] as List).length > 1)
                                              Positioned(
                                                right: 0,
                                                top: 0,
                                                child: Container(
                                                  padding: const EdgeInsets.all(2),
                                                  decoration: const BoxDecoration(
                                                    color: Colors.orange,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Text(
                                                    '${(amenity['images'] as List).length}',
                                                    style: const TextStyle(color: Colors.white, fontSize: 8),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        )
                                      : Icon(_getAmenityIcon(amenityName), color: Colors.blue),
                                  ),
                                  backgroundColor: Colors.blue.shade50,
                                ),
                              );
                            }).toList(),
                          )
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  IconData _getAmenityIcon(String amenity) {
    switch (amenity.toLowerCase()) {
      case 'restroom':
      case 'toilet':
        return Icons.wc;
      case 'atm':
        return Icons.atm;
      case 'convenience store':
      case 'store':
        return Icons.store;
      case 'car wash':
      case 'wash':
        return Icons.local_car_wash;
      case 'tire service':
      case 'tire':
        return Icons.tire_repair;
      case 'oil change':
      case 'oil':
        return Icons.oil_barrel;
      case 'air pump':
      case 'air':
        return Icons.air;
      case 'restaurant':
      case 'food':
        return Icons.restaurant;
      case 'wifi':
        return Icons.wifi;
      case 'parking':
        return Icons.local_parking;
      case '24 hours':
      case '24h':
        return Icons.access_time;
      default:
        return Icons.check_circle;
    }
  }
}
