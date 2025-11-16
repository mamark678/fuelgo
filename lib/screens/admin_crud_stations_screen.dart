import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/firestore_service.dart';

class AdminCRUDStationsScreen extends StatefulWidget {
  const AdminCRUDStationsScreen({Key? key}) : super(key: key);

  @override
  State<AdminCRUDStationsScreen> createState() => _AdminCRUDStationsScreenState();
}

class _AdminCRUDStationsScreenState extends State<AdminCRUDStationsScreen> {
  List<Map<String, dynamic>> _stations = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _showMapView = false;
  final MapController _mapController = MapController();
  bool _isSelectionMode = false;
  Set<String> _selectedStationIds = {};

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final stations = await FirestoreService.getAllGasStations();
      setState(() {
        _stations = stations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading stations: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredStations {
    if (_searchQuery.isEmpty) return _stations;
    final query = _searchQuery.toLowerCase();
    return _stations.where((station) {
      final name = (station['name'] ?? '').toString().toLowerCase();
      final brand = (station['brand'] ?? '').toString().toLowerCase();
      final address = (station['address'] ?? '').toString().toLowerCase();
      return name.contains(query) || brand.contains(query) || address.contains(query);
    }).toList();
  }

  Future<void> _deleteStation(String stationId, String stationName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Station'),
        content: Text('Are you sure you want to delete "$stationName"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirestoreService.deleteGasStation(stationId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Station deleted successfully')),
          );
          _loadStations();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting station: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteSelectedStations() async {
    if (_selectedStationIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No stations selected')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Stations'),
        content: Text(
          'Are you sure you want to delete ${_selectedStationIds.length} station(s)? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final count = _selectedStationIds.length;
        final stationIdsToDelete = _selectedStationIds.toList();
        await FirestoreService.deleteGasStations(stationIdsToDelete);
        if (mounted) {
          setState(() {
            _selectedStationIds.clear();
            _isSelectionMode = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$count station(s) deleted successfully')),
          );
          _loadStations();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting stations: $e')),
          );
        }
      }
    }
  }

  void _toggleSelection(String stationId) {
    setState(() {
      if (_selectedStationIds.contains(stationId)) {
        _selectedStationIds.remove(stationId);
      } else {
        _selectedStationIds.add(stationId);
      }
      // Exit selection mode if no items are selected
      if (_selectedStationIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedStationIds.length == _filteredStations.length) {
        // Deselect all
        _selectedStationIds.clear();
      } else {
        // Select all filtered stations
        _selectedStationIds = _filteredStations.map((s) => s['id'] as String).toSet();
      }
    });
  }

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedStationIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedStationIds.clear();
    });
  }

  void _showEditStationDialog(Map<String, dynamic> station) {
    final nameController = TextEditingController(text: station['name'] ?? '');
    final brandController = TextEditingController(text: station['brand'] ?? '');
    final addressController = TextEditingController(text: station['address'] ?? '');
    final latController = TextEditingController(
      text: station['position']?['latitude']?.toString() ?? '',
    );
    final lngController = TextEditingController(
      text: station['position']?['longitude']?.toString() ?? '',
    );
    final prices = Map<String, double>.from(station['prices'] ?? {});
    final priceControllers = <String, TextEditingController>{};
    prices.forEach((key, value) {
      priceControllers[key] = TextEditingController(text: value.toString());
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Station'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Station Name'),
                ),
                TextField(
                  controller: brandController,
                  decoration: const InputDecoration(labelText: 'Brand'),
                ),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  maxLines: 2,
                ),
                TextField(
                  controller: latController,
                  decoration: const InputDecoration(labelText: 'Latitude'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: lngController,
                  decoration: const InputDecoration(labelText: 'Longitude'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                const Text('Prices:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...priceControllers.entries.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(entry.key),
                      ),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: entry.value,
                          decoration: const InputDecoration(
                            prefixText: '\$',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                )),
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
                try {
                  final updatedPrices = <String, double>{};
                  priceControllers.forEach((key, controller) {
                    final value = double.tryParse(controller.text);
                    if (value != null) {
                      updatedPrices[key] = value;
                    }
                  });

                  // Convert to GeoPoint for Firestore
                  final lat = double.tryParse(latController.text) ?? 0.0;
                  final lng = double.tryParse(lngController.text) ?? 0.0;
                  final geoPoint = GeoPoint(lat, lng);
                  
                  await FirebaseFirestore.instance
                      .collection('gas_stations')
                      .doc(station['id'])
                      .update({
                    'name': nameController.text,
                    'brand': brandController.text,
                    'address': addressController.text,
                    'geoPoint': geoPoint, // Use GeoPoint instead of Map
                    'prices': updatedPrices,
                    'lastUpdated': FieldValue.serverTimestamp(),
                  });

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Station updated successfully')),
                    );
                    _loadStations();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error updating station: $e')),
                    );
                  }
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildMapMarkers() {
    return _filteredStations.map((station) {
      final position = station['position'] as Map<String, dynamic>?;
      if (position == null) return null;
      
      final lat = position['latitude'] as double? ?? 0.0;
      final lng = position['longitude'] as double? ?? 0.0;
      
      return Marker(
        point: LatLng(lat, lng),
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () => _showStationInfoDialog(station),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.local_gas_station,
              color: Colors.blue,
              size: 24,
            ),
          ),
        ),
      );
    }).whereType<Marker>().toList();
  }

  void _showStationInfoDialog(Map<String, dynamic> station) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(station['name'] ?? 'Unknown Station'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Brand: ${station['brand'] ?? 'N/A'}'),
            Text('Address: ${station['address'] ?? 'N/A'}'),
            Text('Owner ID: ${station['ownerId'] ?? 'N/A'}'),
            if (station['prices'] != null)
              Text('Prices: ${(station['prices'] as Map).keys.join(', ')}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showEditStationDialog(station);
            },
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteStation(station['id'], station['name'] ?? 'Unknown');
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  LatLng _getMapCenter() {
    if (_filteredStations.isEmpty) {
      // Default center: Valencia City, Bukidnon, Philippines
      // This provides a reasonable default location for the map when no stations are available
      return const LatLng(7.9055, 125.0908);
    }
    
    final positions = _filteredStations
        .map((s) => s['position'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map((p) => LatLng(
              p['latitude'] as double? ?? 0.0,
              p['longitude'] as double? ?? 0.0,
            ))
        .toList();
    
    if (positions.isEmpty) return const LatLng(7.9055, 125.0908);
    
    double avgLat = positions.map((p) => p.latitude).reduce((a, b) => a + b) / positions.length;
    double avgLng = positions.map((p) => p.longitude).reduce((a, b) => a + b) / positions.length;
    
    return LatLng(avgLat, avgLng);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar and view toggle
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Search stations',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Selection mode controls
                  if (_isSelectionMode) ...[
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _toggleSelectAll,
                          icon: Icon(
                            _selectedStationIds.length == _filteredStations.length
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                          ),
                          label: Text(
                            _selectedStationIds.length == _filteredStations.length
                                ? 'Deselect All'
                                : 'Select All',
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_selectedStationIds.isNotEmpty)
                          ElevatedButton.icon(
                            onPressed: _deleteSelectedStations,
                            icon: const Icon(Icons.delete),
                            label: Text('Delete (${_selectedStationIds.length})'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          ),
                      ],
                    ),
                    TextButton(
                      onPressed: _exitSelectionMode,
                      child: const Text('Cancel'),
                    ),
                  ] else ...[
                    // Normal mode - show selection button
                    if (!_showMapView)
                      TextButton.icon(
                        onPressed: _enterSelectionMode,
                        icon: const Icon(Icons.checklist),
                        label: const Text('Select'),
                      ),
                  ],
                  // View toggle
                  IconButton(
                    icon: Icon(_showMapView ? Icons.list : Icons.map),
                    tooltip: _showMapView ? 'Show List' : 'Show Map',
                    onPressed: () {
                      setState(() {
                        _showMapView = !_showMapView;
                        // Exit selection mode when switching views
                        if (_isSelectionMode) {
                          _isSelectionMode = false;
                          _selectedStationIds.clear();
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Content (List or Map)
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredStations.isEmpty
                  ? const Center(child: Text('No stations found'))
                  : _showMapView
                      ? _buildMapView()
                      : _buildListView(),
        ),
      ],
    );
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _getMapCenter(),
            initialZoom: 13.0,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.fuelgo.app',
            ),
            MarkerLayer(markers: _buildMapMarkers()),
          ],
        ),
        // Info card showing station count
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_filteredStations.length} station${_filteredStations.length != 1 ? 's' : ''} found',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadStations,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListView() {
    return RefreshIndicator(
      onRefresh: _loadStations,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filteredStations.length,
        itemBuilder: (context, index) {
          final station = _filteredStations[index];
          final stationId = station['id'] as String;
          final isSelected = _selectedStationIds.contains(stationId);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: isSelected ? Colors.blue.shade50 : null,
            child: ListTile(
              leading: _isSelectionMode
                  ? Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleSelection(stationId),
                    )
                  : null,
              title: Text(station['name'] ?? 'Unknown'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Brand: ${station['brand'] ?? 'N/A'}'),
                  Text('Address: ${station['address'] ?? 'N/A'}'),
                  Text('Owner ID: ${station['ownerId'] ?? 'N/A'}'),
                  if (station['prices'] != null)
                    Text(
                      'Prices: ${(station['prices'] as Map).keys.join(', ')}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
              trailing: _isSelectionMode
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showEditStationDialog(station),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteStation(
                            stationId,
                            station['name'] ?? 'Unknown',
                          ),
                        ),
                      ],
                    ),
              onTap: _isSelectionMode
                  ? () => _toggleSelection(stationId)
                  : null,
              onLongPress: !_isSelectionMode
                  ? () {
                      setState(() {
                        _isSelectionMode = true;
                        _selectedStationIds.add(stationId);
                      });
                    }
                  : null,
            ),
          );
        },
      ),
    );
  }
}

