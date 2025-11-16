import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

import '../models/gas_station.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gas_station_service.dart';

// Fuel type filter enum
enum FuelTypeFilter {
  all('All Fuel Types'),
  regularOnly('Only Regular'),
  premiumOnly('Only Premium'),
  dieselOnly('Only Diesel'),
  regularAndPremium('Regular & Premium'),
  premiumAndDiesel('Premium & Diesel'),
  regularAndDiesel('Regular & Diesel');

  final String label;
  const FuelTypeFilter(this.label);
}

class OwnerStationMapSelectScreen extends StatefulWidget {
  const OwnerStationMapSelectScreen({Key? key}) : super(key: key);

  @override
  State<OwnerStationMapSelectScreen> createState() => _OwnerStationMapSelectScreenState();
}

class _OwnerStationMapSelectScreenState extends State<OwnerStationMapSelectScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final Location _location = Location();
  
  String? _selectedStationName;
  String? _selectedAddress;
  LatLng? _selectedLatLng;
  String? _selectedStationId;
  List<GasStation> _gasStations = [];
  List<GasStation> _ownerStations = [];
  List<GasStation> _filteredStations = [];
  List<GasStation> _nearbyStations = [];
  bool _isLoading = true;
  bool _showOwnerStationsOnly = false;
  bool _showNearbyList = false;
  bool _isGettingLocation = false;
  LatLng? _currentLocation;
  double _currentZoom = 14.0;
  FuelTypeFilter? _selectedFuelTypeFilter;

  // REMOVED: Default location center
  // Map will use current location or center on selected/available stations

  @override
  void initState() {
    super.initState();
    _loadAllStations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _filterStations();
  }

  void _filterStations() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      List<GasStation> stations = _gasStations;

      // Apply search filter
      if (query.isNotEmpty) {
        stations = stations.where((station) {
          return (station.name?.toLowerCase().contains(query) ?? false) ||
              (station.brand?.toLowerCase().contains(query) ?? false) ||
              (station.address?.toLowerCase().contains(query) ?? false);
        }).toList();
      }

      // Apply fuel type filter
      if (_selectedFuelTypeFilter != null && _selectedFuelTypeFilter != FuelTypeFilter.all) {
        stations = stations.where((station) {
          return _stationMatchesFuelTypeFilter(station, _selectedFuelTypeFilter!);
        }).toList();
      }

      _filteredStations = stations;
      _updateNearbyStations();
    });
  }

  // Check if a station matches the selected fuel type filter
  bool _stationMatchesFuelTypeFilter(GasStation station, FuelTypeFilter filter) {
    if (station.prices == null || station.prices!.isEmpty) return false;

    // Normalize fuel type keys to lowercase for comparison
    final availableFuelTypes = station.prices!.keys.map((k) => k.toLowerCase()).toSet();

    switch (filter) {
      case FuelTypeFilter.regularOnly:
        return availableFuelTypes.contains('regular') && 
               !availableFuelTypes.contains('premium') && 
               !availableFuelTypes.contains('diesel');
      
      case FuelTypeFilter.premiumOnly:
        return availableFuelTypes.contains('premium') && 
               !availableFuelTypes.contains('regular') && 
               !availableFuelTypes.contains('diesel');
      
      case FuelTypeFilter.dieselOnly:
        return availableFuelTypes.contains('diesel') && 
               !availableFuelTypes.contains('regular') && 
               !availableFuelTypes.contains('premium');
      
      case FuelTypeFilter.regularAndPremium:
        return availableFuelTypes.contains('regular') && 
               availableFuelTypes.contains('premium') &&
               !availableFuelTypes.contains('diesel');
      
      case FuelTypeFilter.premiumAndDiesel:
        return availableFuelTypes.contains('premium') && 
               availableFuelTypes.contains('diesel') &&
               !availableFuelTypes.contains('regular');
      
      case FuelTypeFilter.regularAndDiesel:
        return availableFuelTypes.contains('regular') && 
               availableFuelTypes.contains('diesel') &&
               !availableFuelTypes.contains('premium');
      
      case FuelTypeFilter.all:
        return true;
    }
  }

  void _updateNearbyStations() {
    if (_selectedLatLng == null) {
      _nearbyStations = [];
      return;
    }

    final stations = _displayedStations.map((station) {
      final distance = _calculateDistance(
        _selectedLatLng!.latitude,
        _selectedLatLng!.longitude,
        station.position.latitude,
        station.position.longitude,
      );
      return MapEntry(station, distance);
    }).toList();

    stations.sort((a, b) => a.value.compareTo(b.value));
    _nearbyStations = stations.take(5).map((e) => e.key).toList();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
    });

    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location services are disabled. Please enable them in settings.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission denied. Please grant location access.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      final locationData = await _location.getLocation();
      final currentLatLng = LatLng(locationData.latitude!, locationData.longitude!);

      setState(() {
        _currentLocation = currentLatLng;
      });

      // Animate map to current location
      _mapController.move(currentLatLng, _currentZoom);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📍 Centered on your current location'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error getting current location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isGettingLocation = false;
      });
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedLatLng = null;
      _selectedStationName = null;
      _selectedAddress = null;
      _selectedStationId = null;
      _nearbyStations = [];
    });
  }

  // Get price ranges for color coding
  Map<String, double> _getPriceRanges() {
    final prices = _displayedStations
        .map((s) => s.prices?['Regular'])
        .where((p) => p != null)
        .cast<double>()
        .toList();

    if (prices.isEmpty) return {'cheap': 50.0, 'expensive': 70.0};

    prices.sort();

    return {
      'cheap': prices[(prices.length / 3).floor()],
      'expensive': prices[(prices.length * 2 / 3).floor()],
    };
  }

  // Color coding: Green = cheap, Yellow = medium, Red = expensive
  Color _colorForPriceWithRanges(double price, Map<String, double> ranges) {
    if (price <= ranges['cheap']!) return Colors.green;
    if (price <= ranges['expensive']!) return Colors.yellow; // Changed from orange to yellow
    return Colors.red;
  }

  // Animated marker widget for gas station (optimized for performance)
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
      // Use price-based color coding for public stations
      final price = gasStation.prices?['Regular'];
      if (price != null) {
        final ranges = _getPriceRanges();
        markerColor = _colorForPriceWithRanges(price, ranges);
      } else {
        // Brand-based colors as fallback
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
    }

    // Get price for display (use Regular as default)
    final price = gasStation.prices?['Regular'];
    final ranges = _getPriceRanges();

    return RepaintBoundary(
      child: _GasStationMarkerWidget(
        station: gasStation,
        markerColor: markerColor,
        price: price,
        priceRanges: ranges,
        rating: gasStation.rating ?? 0.0,
        isOpen: gasStation.isOpen,
        isSelected: isSelected,
        isOwnedByCurrentUser: isOwnedByCurrentUser,
        isOwnerCreated: isOwnerCreated,
        onTap: onTap,
      ),
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
      // Load all available stations for signup selection
      final allStations = await _loadAllAvailableStations();
      
      setState(() {
        _gasStations = allStations;
        _ownerStations = []; // Empty for signup - showing all available stations
        _filteredStations = allStations;
        _isLoading = false;
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
      // Load only approved stations from Firestore
      // Map starts empty - stations only appear when owners register and are approved
      final firestoreStations = await _loadFirestoreStations();
      allStations.addAll(firestoreStations);
      
      // COMMENTED OUT: Loading OSM stations
      // For document submission, owners should select location manually or use current location
      // Gas stations should only appear when owners register and are approved
      /*
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
      */
      
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
      
      // Filter stations to only include those from approved owners
      // Use ownerApprovalStatus field stored in gas_station document (avoids permission issues)
      for (final stationData in firestoreStations) {
        final ownerApprovalStatus = stationData['ownerApprovalStatus'] as String? ?? 'pending';
        
        // Only include stations from approved owners
        if (ownerApprovalStatus != 'approved') {
          continue; // Skip this station
        }
        
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
        
        final prices = <String, double>{};
        final rawPrices = stationData['prices'];
        if (rawPrices is Map) {
          rawPrices.forEach((key, value) {
            final normalizedKey = key.toString().trim().toLowerCase();
            if (normalizedKey.isEmpty) return;
            double? parsed;
            if (value is num) {
              parsed = value.toDouble();
            } else if (value != null) {
              parsed = double.tryParse(value.toString());
            }
            if (parsed == null || !parsed.isFinite || parsed.isNaN) return;
            if (parsed < 0) parsed = 0;
            prices[normalizedKey] = parsed;
          });
        }
        
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

  // COMMENTED OUT: Loading OSM stations with randomized prices
  // For document submission, owners should select location manually or use current location
  // Gas stations should only appear when owners register and are approved
  /*
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
        
        // COMMENTED OUT: Randomizer for OSM station prices
        // Prices should come from actual gas station owners, not randomized
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
  */

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

  List<GasStation> get _displayedStations {
    if (_showOwnerStationsOnly) {
      return _ownerStations;
    }
    return _filteredStations.isEmpty ? _gasStations : _filteredStations;
  }

  // Replace _markers getter with flutter_map markers
  List<Marker> get _markers {
    final user = AuthService().currentUser;
    final currentUserId = user?.uid;
    final List<Marker> markers = [];

    // Add existing station markers with animated marker widget
    markers.addAll(_displayedStations.map((station) {
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
              _selectedAddress = station.address;
            });
            _updateNearbyStations();
            _mapController.move(station.position, _currentZoom);
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
    _updateNearbyStations();
    _showCustomStationNameDialog();
  }

  void _showCustomStationNameDialog() {
    final TextEditingController nameController = TextEditingController(text: _selectedStationName);
    final TextEditingController addressController = TextEditingController(text: _selectedAddress);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_location, color: Colors.blue),
            SizedBox(width: 8),
            Text('Default Location'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter details for your new gas station:',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Station Name *',
                  hintText: 'e.g., Petron Station',
                  prefixIcon: Icon(Icons.local_gas_station),
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address (Optional)',
                  hintText: 'e.g., Street Address, City',
                  prefixIcon: Icon(Icons.location_on),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Coordinates: ${_selectedLatLng?.latitude.toStringAsFixed(6)}, ${_selectedLatLng?.longitude.toStringAsFixed(6)}',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedLatLng = null;
                _selectedStationName = null;
                _selectedAddress = null;
              });
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                setState(() {
                  _selectedStationName = nameController.text.trim();
                  _selectedAddress = addressController.text.trim();
                });
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a station name'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
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
                _clearSelection();
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
                // Search bar
                Container(
                  padding: const EdgeInsets.all(12.0),
                  color: Colors.white,
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search stations by name, brand, or address...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        onChanged: (_) => setState(() {}), // Rebuild to show/hide clear button
                      ),
                      const SizedBox(height: 8),
                      // Fuel type filter dropdown
                      DropdownButtonFormField<FuelTypeFilter?>(
                        value: _selectedFuelTypeFilter,
                        decoration: InputDecoration(
                          labelText: 'Filter by Fuel Type',
                          prefixIcon: const Icon(Icons.filter_alt),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        items: [
                          const DropdownMenuItem<FuelTypeFilter?>(
                            value: null,
                            child: Text('All Fuel Types'),
                          ),
                          ...FuelTypeFilter.values.map((filter) {
                            return DropdownMenuItem<FuelTypeFilter?>(
                              value: filter,
                              child: Text(filter.label),
                            );
                          }),
                        ],
                        onChanged: (FuelTypeFilter? value) {
                          setState(() {
                            _selectedFuelTypeFilter = value;
                            _filterStations();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      // Instructions
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tap on a station marker to select it, or tap anywhere on the map to create a new location',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
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
                        Expanded(
                          child: Text(
                            'Showing ${_filteredStations.isEmpty ? _gasStations.length : _filteredStations.length} available stations${_selectedFuelTypeFilter != null && _selectedFuelTypeFilter != FuelTypeFilter.all ? ' (${_selectedFuelTypeFilter!.label})' : ''}',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (_selectedFuelTypeFilter != null && _selectedFuelTypeFilter != FuelTypeFilter.all)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _selectedFuelTypeFilter = null;
                                _filterStations();
                              });
                            },
                            tooltip: 'Clear fuel type filter',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ),
                
                // Map
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          // Use current location if available, otherwise use Valencia City, Bukidnon as default
                          initialCenter: _currentLocation ?? const LatLng(7.9055, 125.0908),
                          initialZoom: _currentZoom,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all,
                          ),
                          onTap: (tapPosition, point) => _onMapTap(point),
                          onMapEvent: (event) {
                            if (event is MapEventMove) {
                              _currentZoom = event.camera.zoom;
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c'],
                          ),
                          MarkerLayer(
                            markers: _markers,
                          ),
                          // Current location marker
                          if (_currentLocation != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _currentLocation!,
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.3),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.my_location,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      // Floating action buttons
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'location',
                              onPressed: _isGettingLocation ? null : _getCurrentLocation,
                              backgroundColor: Colors.white,
                              child: _isGettingLocation
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.my_location, color: Colors.blue),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: 'zoom_in',
                              onPressed: () {
                                _currentZoom = (_currentZoom + 1).clamp(3.0, 18.0);
                                _mapController.move(_mapController.camera.center, _currentZoom);
                              },
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.zoom_in, color: Colors.blue),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: 'zoom_out',
                              onPressed: () {
                                _currentZoom = (_currentZoom - 1).clamp(3.0, 18.0);
                                _mapController.move(_mapController.camera.center, _currentZoom);
                              },
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.zoom_out, color: Colors.blue),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Nearby stations list (collapsible)
                if (_nearbyStations.isNotEmpty && _selectedLatLng != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    height: _showNearbyList ? 200 : 0,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300),
                        bottom: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showNearbyList = !_showNearbyList;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.near_me,
                                  size: 18,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Nearby Stations (${_nearbyStations.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  _showNearbyList ? Icons.expand_less : Icons.expand_more,
                                  color: Colors.grey.shade600,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showNearbyList)
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              itemCount: _nearbyStations.length,
                              itemBuilder: (context, index) {
                                final station = _nearbyStations[index];
                                final distance = _calculateDistance(
                                  _selectedLatLng!.latitude,
                                  _selectedLatLng!.longitude,
                                  station.position.latitude,
                                  station.position.longitude,
                                );
                                return ListTile(
                                  leading: Icon(
                                    Icons.local_gas_station,
                                    color: Colors.blue.shade700,
                                  ),
                                  title: Text(
                                    station.name ?? 'Unknown Station',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Text(
                                    '${distance.toStringAsFixed(2)} km away',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                  trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                                  onTap: () {
                                    setState(() {
                                      _selectedLatLng = station.position;
                                      _selectedStationName = station.name;
                                      _selectedStationId = station.id;
                                      _selectedAddress = station.address;
                                    });
                                    _mapController.move(station.position, _currentZoom);
                                    _updateNearbyStations();
                                  },
                                );
                              },
                            ),
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
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Selected Station:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    color: Colors.grey.shade600,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: _clearSelection,
                                    tooltip: 'Clear Selection',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedStationName!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_selectedAddress != null && _selectedAddress!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _selectedAddress!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                              if (_selectedLatLng != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '📍 ${_selectedLatLng!.latitude.toStringAsFixed(6)}, ${_selectedLatLng!.longitude.toStringAsFixed(6)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade500,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      Row(
                        children: [
                          if (_selectedStationName != null)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _clearSelection,
                                icon: const Icon(Icons.clear),
                                label: const Text('Clear'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                          if (_selectedStationName != null) const SizedBox(width: 12),
                          Expanded(
                            flex: _selectedStationName != null ? 2 : 1,
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
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// Gas station marker widget (optimized for performance)
class _GasStationMarkerWidget extends StatefulWidget {
  final GasStation station;
  final Color markerColor;
  final double? price;
  final Map<String, double> priceRanges;
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
    required this.priceRanges,
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

class _GasStationMarkerWidgetState extends State<_GasStationMarkerWidget> {
  bool _isPressed = false;

  // Optimized: Use dynamic price ranges instead of hardcoded values
  // Color coding: Green = cheap, Yellow = medium, Red = expensive
  Color _getPriceBadgeColor(double price) {
    if (price <= widget.priceRanges['cheap']!) return Colors.green;
    if (price <= widget.priceRanges['expensive']!) return Colors.yellow; // Changed from orange to yellow
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
      child: Transform.scale(
        scale: _isPressed ? 0.93 : 1.0, // Simplified: removed continuous animation
        child: SizedBox(
          width: 56 * s,
          height: 56 * s,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Static ring if open (removed pulsing animation for performance)
              if (widget.isOpen)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.markerColor.withOpacity(0.15), // Reduced opacity for less visual weight
                        width: 2 * s, // Thinner border
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
                            color: Colors.black.withOpacity(0.2), // Reduced opacity
                            blurRadius: 4, // Reduced blur
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
                              color: Colors.black.withOpacity(0.15), // Reduced opacity
                              blurRadius: 4, // Reduced blur
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

                  // brand initial (top-left) - only show if not using price-based color
                  if (widget.station.brand != null && 
                      widget.station.brand!.isNotEmpty && 
                      widget.price == null)
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
                              color: Colors.black.withOpacity(0.15), // Reduced opacity
                              blurRadius: 3, // Reduced blur
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