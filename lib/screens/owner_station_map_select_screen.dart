import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/gas_station.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gas_station_service.dart';

class OwnerStationMapSelectScreen extends StatefulWidget {
  const OwnerStationMapSelectScreen({Key? key}) : super(key: key);

  @override
  State<OwnerStationMapSelectScreen> createState() => _OwnerStationMapSelectScreenState();
}

class _OwnerStationMapSelectScreenState extends State<OwnerStationMapSelectScreen> {
  // Remove GoogleMapController
  // GoogleMapController? _mapController;
  String? _selectedStationName;
  LatLng? _selectedLatLng;
  String? _selectedStationId;
  List<GasStation> _gasStations = [];
  List<GasStation> _ownerStations = [];
  bool _isLoading = true;
  bool _showOwnerStationsOnly = false;

  // Use a regular field for Valencia City center
  final LatLng _valenciaCityCenter = LatLng(7.9061, 125.0946); // Valencia City, Bukidnon

  @override
  void initState() {
    super.initState();
    _loadAllStations();
  }

  // Animated marker widget for gas station (adapted from map_tab.dart)
  Widget _AnimatedGasStationMarker({
    required GasStation gasStation,
    required bool isSelected,
    required bool isOwnedByCurrentUser,
    required bool isOwnerCreated,
    required VoidCallback onTap,
  }) {
    // Determine marker color based on selection and ownership
    Color markerColor;
    if (isSelected) {
      markerColor = Colors.red;
    } else if (isOwnedByCurrentUser) {
      markerColor = Colors.lightBlue;
    } else if (isOwnerCreated) {
      markerColor = Colors.cyan;
    } else {
      // Brand-based colors for public stations
      switch (gasStation.brand?.toLowerCase() ?? '') {
        case 'shell':
          markerColor = Colors.yellow;
          break;
        case 'petron':
          markerColor = Colors.blue;
          break;
        case 'caltex':
          markerColor = Colors.green;
          break;
        case 'phoenix':
          markerColor = Colors.orange;
          break;
        default:
          markerColor = Colors.purple;
      }
    }

    // Get price for display (use Regular as default)
    final price = gasStation.prices?['Regular'];

    return _GasStationMarkerWidget(
      station: gasStation,
      markerColor: markerColor,
      price: price,
      rating: gasStation.rating ?? 0.0,
      isOpen: gasStation.isOpen,
      isSelected: isSelected,
      isOwnedByCurrentUser: isOwnedByCurrentUser,
      isOwnerCreated: isOwnerCreated,
      onTap: onTap,
    );
  }

  // Custom marker widget for user-selected location with custom name
  Widget _CustomGasStationMarker({
    required String stationName,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, color: Colors.redAccent, size: 36),
          Text(
            stationName,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _loadAllStations() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load all available stations in Valencia City, Bukidnon for signup selection
      final allStations = await _loadAllAvailableStations();
      
      setState(() {
        _gasStations = allStations;
        _ownerStations = []; // Empty for signup - showing all available stations
        _isLoading = false;
        
        // Auto-focus on Valencia City area
        // if (_mapController != null) {
        //   _focusOnValenciaCity();
        // }
      });
    } catch (e) {
      print('Error loading stations: $e');
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading stations: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // void _focusOnValenciaCity() {
  //   if (_mapController == null) return;
    
  //   // Center on Valencia City, Bukidnon
  //   _mapController!.animateCamera(
  //     CameraUpdate.newLatLngZoom(
  //       const LatLng(7.9061, 125.0946),
  //       14.0,
  //     ),
  //   );
  // }

  // void _focusOnOwnerStations() {
  //   if (_ownerStations.isEmpty || _mapController == null) return;
    
  //   if (_ownerStations.length == 1) {
  //     // Center on single station
  //     _mapController!.animateCamera(
  //       CameraUpdate.newLatLngZoom(
  //         _ownerStations.first.position,
  //         16.0,
  //       ),
  //     );
  //   } else {
  //     // Fit all owner stations in view
  //     double minLat = _ownerStations.first.position.latitude;
  //     double maxLat = _ownerStations.first.position.latitude;
  //     double minLng = _ownerStations.first.position.longitude;
  //     double maxLng = _ownerStations.first.position.longitude;
      
  //     for (final station in _ownerStations) {
  //       minLat = math.min(minLat, station.position.latitude);
  //       maxLat = math.max(maxLat, station.position.latitude);
  //       minLng = math.min(minLng, station.position.longitude);
  //       maxLng = math.max(maxLng, station.position.longitude);
  //     }
      
  //     _mapController!.animateCamera(
  //       CameraUpdate.newLatLngBounds(
  //         LatLngBounds(
  //           southwest: LatLng(minLat - 0.01, minLng - 0.01),
  //           northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
  //         ),
  //         100.0,
  //       ),
  //     );
  //   }
  // }

  Future<List<GasStation>> _loadAllAvailableStations() async {
    final List<GasStation> allStations = [];
    
    try {
      // 1. Load stations from Firestore (all owner-created stations)
      final firestoreStations = await _loadFirestoreStations();
      allStations.addAll(firestoreStations);
      
      // 2. Load stations from OpenStreetMap
      final osmStations = await _loadOpenStreetMapStations();
      
      // Filter out OSM stations that are too close to Firestore stations
      for (final osmStation in osmStations) {
        bool isDuplicate = false;
        for (final firestoreStation in firestoreStations) {
          final distance = _calculateDistance(
            osmStation.position.latitude,
            osmStation.position.longitude,
            firestoreStation.position.latitude,
            firestoreStation.position.longitude,
          );
          
          if (distance < 0.1) { // Less than 100 meters
            isDuplicate = true;
            break;
          }
        }
        
        if (!isDuplicate) {
          allStations.add(osmStation);
        }
      }
      
    } catch (e) {
      print('Error loading all stations: $e');
      // Fallback to GasStationService
      await GasStationService.fetchAndCacheGasStations();
      allStations.addAll(GasStationService.getAllGasStations());
    }

    return allStations;
  }

  Future<List<GasStation>> _loadFirestoreStations() async {
    try {
      final firestoreStations = await FirestoreService.getAllGasStations();
      final List<GasStation> stations = [];
      
      for (final stationData in firestoreStations) {
        final position = stationData['position'];
        LatLng latLng;
        
        if (position is Map) {
          latLng = LatLng(
            position['latitude']?.toDouble() ?? 0.0,
            position['longitude']?.toDouble() ?? 0.0,
          );
        } else {
          latLng = LatLng(position.latitude, position.longitude);
        }
        
        final prices = Map<String, double>.from(stationData['prices'] ?? {});
        
        final gasStation = GasStation(
          id: stationData['id'] ?? '',
          name: stationData['stationName'] ?? stationData['name'] ?? 'Gas Station',
          brand: stationData['brand'] ?? 'Unknown',
          address: stationData['address'] ?? 'No address',
          position: latLng,
          prices: prices,
          rating: (stationData['rating'] ?? 4.0).toDouble(),
          isOpen: stationData['isOpen'] ?? true,
          offers: [], // Initialize with empty list
          vouchers: [], // Initialize with empty list
          services: List<String>.from(stationData['services'] ?? []),
          isOwnerCreated: true,
          ownerId: stationData['ownerId'], // Track which owner created this
        );
        
        stations.add(gasStation);
      }
      
      return stations;
    } catch (e) {
      print('Error loading Firestore stations: $e');
      return [];
    }
  }

  Future<List<GasStation>> _loadOwnerStations(String ownerId) async {
    try {
      final ownerStations = await FirestoreService.getGasStationsByOwner(ownerId);
      final List<GasStation> stations = [];
      
      for (final stationData in ownerStations) {
        final position = stationData['position'];
        LatLng latLng;
        
        if (position is Map) {
          latLng = LatLng(
            position['latitude']?.toDouble() ?? 0.0,
            position['longitude']?.toDouble() ?? 0.0,
          );
        } else {
          latLng = LatLng(position.latitude, position.longitude);
        }
        
        final prices = Map<String, double>.from(stationData['prices'] ?? {});
        
        final gasStation = GasStation(
          id: stationData['id'] ?? '',
          name: stationData['stationName'] ?? stationData['name'] ?? 'Gas Station',
          brand: stationData['brand'] ?? 'Unknown',
          address: stationData['address'] ?? 'No address',
          position: latLng,
          prices: prices,
          rating: (stationData['rating'] ?? 4.0).toDouble(),
          isOpen: stationData['isOpen'] ?? true,
          offers: [], // Empty list of Offer objects
          vouchers: [], // Empty list of Voucher objects
          services: List<String>.from(stationData['services'] ?? []),
          isOwnerCreated: true,
          ownerId: stationData['ownerId'],
        );
        
        stations.add(gasStation);
      }
      
      return stations;
    } catch (e) {
      print('Error loading owner stations: $e');
      return [];
    }
  }

  Future<List<GasStation>> _loadOpenStreetMapStations() async {
    const bbox = '7.85,125.00,7.95,125.15';
    final query = '''
      [out:json][timeout:30];
      (
        node["amenity"="fuel"]($bbox);
        way["amenity"="fuel"]($bbox);
        relation["amenity"="fuel"]($bbox);
      );
      out center;
    ''';

    try {
      final res = await http
          .post(
            Uri.parse('https://overpass-api.de/api/interpreter'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 30));
      
      if (res.statusCode != 200) throw Exception('Failed to load OSM stations');

      final elems = json.decode(res.body)['elements'] as List;
      final List<GasStation> stations = [];

      for (final el in elems) {
        final id = 'osm_${el['id']}';
        final tags = el['tags'] ?? <String, dynamic>{};
        final name = tags['name'] ?? 'Gas Station';
        final brand = tags['brand'] ?? 'Unknown';
        final address = tags['addr:full'] ?? 'Valencia City, Bukidnon';
        final lat = el['lat'] ?? el['center']['lat'];
        final lon = el['lon'] ?? el['center']['lon'];
        final position = LatLng(lat, lon);
        
        // Generate default prices for OSM stations
        final prices = {
          'Regular': 55.50 + (math.Random().nextDouble() * 5),
          'Premium': 60.00 + (math.Random().nextDouble() * 5),
          'Diesel': 52.00 + (math.Random().nextDouble() * 5),
        };

        final gasStation = GasStation(
          id: id,
          name: name,
          brand: brand,
          address: address,
          position: position,
          prices: prices,
          rating: 4.0 + (math.Random().nextDouble() * 1.0),
          isOpen: true,
          offers: [],
          vouchers: [],
          services: [],
          isOwnerCreated: false,
        );

        stations.add(gasStation);
      }

      return stations;
    } catch (e) {
      print('Error loading OSM stations: $e');
      return [];
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double radiusOfEarth = 6371;
    
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return radiusOfEarth * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  List<GasStation> get _filteredStations {
    if (_showOwnerStationsOnly) {
      return _ownerStations;
    }
    return _gasStations;
  }

  // Replace _markers getter with flutter_map markers
  List<Marker> get _markers {
    final user = AuthService().currentUser;
    final currentUserId = user?.uid;
    final List<Marker> markers = [];

    // Add existing station markers with animated marker widget
    markers.addAll(_filteredStations.map((station) {
      final bool isSelected = _selectedLatLng != null &&
          station.position.latitude == _selectedLatLng!.latitude &&
          station.position.longitude == _selectedLatLng!.longitude;

      final bool isOwnedByCurrentUser = station.ownerId == currentUserId;
      final bool isOwnerCreated = station.isOwnerCreated ?? false;

      return Marker(
        point: station.position,
        width: 60,
        height: 60,
        child: _AnimatedGasStationMarker(
          gasStation: station,
          isSelected: isSelected,
          isOwnedByCurrentUser: isOwnedByCurrentUser,
          isOwnerCreated: isOwnerCreated,
          onTap: () {
            setState(() {
              _selectedLatLng = station.position;
              _selectedStationName = station.name;
              _selectedStationId = station.id;
            });
          },
        ),
      );
    }));

    // Add custom selected location marker if any
    if (_selectedLatLng != null && _selectedStationId == null && _selectedStationName != null) {
      markers.add(
        Marker(
          point: _selectedLatLng!,
          width: 60,
          height: 60,
          child: _CustomGasStationMarker(
            stationName: _selectedStationName!,
            onTap: () {},
          ),
        ),
      );
    }

    return markers;
  }

  void _onConfirm() {
    if (_selectedLatLng != null && _selectedStationName != null) {
      Navigator.pop(context, {
        'stationId': _selectedStationId,
        'stationName': _selectedStationName!,
        'lat': _selectedLatLng!.latitude,
        'lng': _selectedLatLng!.longitude,
      });
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _selectedLatLng = point;
      _selectedStationId = null; // custom
    });
    _showCustomStationNameDialog();
  }

  void _showCustomStationNameDialog() {
    final TextEditingController controller = TextEditingController(text: _selectedStationName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Station Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Gas Station Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _selectedStationName = controller.text.trim();
                });
              }
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Station Location'),
        actions: [
          IconButton(
            icon: Icon(_showOwnerStationsOnly ? Icons.all_inclusive : Icons.person),
            onPressed: () {
              setState(() {
                _showOwnerStationsOnly = !_showOwnerStationsOnly;
                // Clear selection when switching views
                _selectedLatLng = null;
                _selectedStationName = null;
                _selectedStationId = null;
              });
            },
            tooltip: _showOwnerStationsOnly ? 'Show All Stations' : 'Show My Stations Only',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllStations,
            tooltip: 'Refresh Stations',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filter indicator
                if (_showOwnerStationsOnly)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8.0),
                    color: Colors.blue.shade100,
                    child: Row(
                      children: [
                        Icon(Icons.person, size: 16, color: Colors.blue.shade800),
                        const SizedBox(width: 8),
                        Text(
                          'Showing your stations only (${_ownerStations.length} stations)',
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8.0),
                    color: Colors.grey.shade100,
                    child: Row(
                      children: [
                        Icon(Icons.all_inclusive, size: 16, color: Colors.grey.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Showing all available stations (${_gasStations.length} stations)',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                // Map
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: _valenciaCityCenter,
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                      onTap: (tapPosition, point) => _onMapTap(point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                      ),
                      MarkerLayer(
                        markers: _markers,
                      ),
                    ],
                  ),
                ),
                
                // Selection info and confirm button
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        spreadRadius: 1,
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Legend
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _LegendItem(
                            color: Colors.lightBlue,
                            label: 'Your Stations',
                          ),
                          _LegendItem(
                            color: Colors.cyan,
                            label: 'Other Owners',
                          ),
                          _LegendItem(
                            color: Colors.grey,
                            label: 'Public Stations',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      if (_selectedStationName != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Selected Station:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedStationName!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _selectedLatLng != null ? _onConfirm : null,
                          icon: const Icon(Icons.check),
                          label: const Text('Confirm Location'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// Gas station marker widget (adapted from map_tab.dart)
class _GasStationMarkerWidget extends StatefulWidget {
  final GasStation station;
  final Color markerColor;
  final double? price;
  final double rating;
  final bool isOpen;
  final bool isSelected;
  final bool isOwnedByCurrentUser;
  final bool isOwnerCreated;
  final VoidCallback onTap;

  const _GasStationMarkerWidget({
    required this.station,
    required this.markerColor,
    required this.price,
    required this.rating,
    required this.isOpen,
    required this.isSelected,
    required this.isOwnedByCurrentUser,
    required this.isOwnerCreated,
    required this.onTap,
  });

  @override
  State<_GasStationMarkerWidget> createState() => _GasStationMarkerWidgetState();
}

class _GasStationMarkerWidgetState extends State<_GasStationMarkerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.08,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _pulseAnimation = Tween<double>(
      begin: 0.9,
      end: 1.15,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Color _getPriceBadgeColor(double price) {
    if (price <= 55) return Colors.green;
    if (price <= 60) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final s = 1.0; // Scale factor
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _isPressed = true;
        });
      },
      onTapUp: (_) {
        setState(() {
          _isPressed = false;
        });
        widget.onTap();
      },
      onTapCancel: () {
        setState(() {
          _isPressed = false;
        });
      },
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _isPressed ? 0.93 : _scaleAnimation.value,
            child: SizedBox(
              width: 56 * s,
              height: 56 * s,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // pulsing ring if open
                  if (widget.isOpen)
                    Positioned.fill(
                      child: Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: widget.markerColor.withOpacity(0.18),
                              width: 3 * s,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // main circle
                  Center(
                    child: Container(
                      width: 46 * s,
                      height: 46 * s,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(
                          color: widget.markerColor,
                          width: widget.isOwnerCreated ? 4 * s : 3 * s,
                        ),
                      ),
                      child: Icon(
                        widget.isOwnerCreated ? Icons.local_gas_station : Icons.local_gas_station_outlined,
                        color: widget.markerColor,
                        size: 22 * s,
                      ),
                    ),
                  ),

                  // price badge (top-right)
                  if (widget.price != null)
                    Positioned(
                      right: -2 * s,
                      top: -2 * s,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 3 * s),
                        decoration: BoxDecoration(
                          color: _getPriceBadgeColor(widget.price!),
                          borderRadius: BorderRadius.circular(10 * s),
                          border: Border.all(color: Colors.white, width: 1.2 * s),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          '₱${widget.price!.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10 * s,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  // open/closed dot (bottom-right)
                  Positioned(
                    right: -2 * s,
                    bottom: -2 * s,
                    child: Container(
                      width: 14 * s,
                      height: 14 * s,
                      decoration: BoxDecoration(
                        color: widget.isOpen ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2 * s),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // brand initial (top-left)
                  if (widget.station.brand != null && widget.station.brand!.isNotEmpty)
                    Positioned(
                      left: -6 * s,
                      top: -6 * s,
                      child: Container(
                        width: 22 * s,
                        height: 22 * s,
                        decoration: BoxDecoration(
                          color: widget.markerColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1 * s),
                        ),
                        child: Center(
                          child: Text(
                            widget.station.brand![0].toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11 * s,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // rating display (bottom-left)
                  if (widget.rating > 0)
                    Positioned(
                      left: -6 * s,
                      bottom: -6 * s,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 2 * s),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade600,
                          borderRadius: BorderRadius.circular(8 * s),
                          border: Border.all(color: Colors.white, width: 1 * s),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              color: Colors.white,
                              size: 10 * s,
                            ),
                            SizedBox(width: 2 * s),
                            Text(
                              widget.rating.toStringAsFixed(1),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9 * s,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Selection indicator for selected stations
                  if (widget.isSelected)
                    Positioned(
                      top: -8 * s,
                      child: Container(
                        width: 20 * s,
                        height: 20 * s,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2 * s),
                        ),
                        child: Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 12 * s,
                        ),
                      ),
                    ),

                  // Ownership indicators
                  if (widget.isOwnedByCurrentUser)
                    Positioned(
                      left: -8 * s,
                      child: Container(
                        width: 16 * s,
                        height: 16 * s,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2 * s),
                        ),
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 8 * s,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}