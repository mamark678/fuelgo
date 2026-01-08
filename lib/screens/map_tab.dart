import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/gas_station.dart';
import '../screens/list_screen.dart';
import '../services/firestore_service.dart';
import '../services/navigation_service.dart';
import '../services/user_interaction_service.dart';

// Fuel type filter enum for filtering stations by available fuel types
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

class MapTab extends StatefulWidget {
  final List<Map<String, dynamic>> assignedStations;
  final Function(GasStation)? onNavigateToStation; // ✅ Define it here

  const MapTab({
    super.key,
    required this.assignedStations,
    this.onNavigateToStation,
  });

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  final MapController _mapController = MapController();
  bool _showNavigationDashboard = false;
  String _routeStatus = 'Calculating route...';
  Duration? _trafficAdjustedTime;
  String _nextInstruction = '';
  double _currentSpeed = 0.0;
  int _trafficLevel = 0; // 0 = none, 1 = light, 2 = moderate, 3 = heavy
  bool _isMapLocked = true; // Default to locked during navigation
  Timer? _locationUpdateTimer;

  double? _distanceToStationKm;
  Duration? _estimatedArrivalTime;

  void _navigateToGasStationDetail(GasStation station) {
    // Validate station data and prevent navigation with placeholder values
    final stationId = station.id?.isNotEmpty == true ? station.id : null;
    final stationName = station.name?.isNotEmpty == true ? station.name : null;

    // Don't navigate if we have placeholder data
    if (stationId == null &&
        (stationName == null ||
            stationName == 'GAS_STATION_ID' ||
            stationName.contains('GAS_STATION'))) {
      print(
          '[ERROR] Cannot navigate to station with invalid data: id=$stationId, name=$stationName');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Unable to load station details. Please try again.')),
      );
      return;
    }

    // Use station ID if available, otherwise use name (but validate it's not placeholder)
    final navigationId = stationId ?? stationName;

    if (navigationId == null || navigationId.isEmpty) {
      print('[ERROR] No valid station identifier found');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Station information is incomplete.')),
      );
      return;
    }

    print(
        '[DEBUG] Navigating to station: id=$stationId, name=$stationName, using=$navigationId');

    // Track station click interaction
    if (stationId != null && stationName != null) {
      UserInteractionService.trackStationClick(
        stationId: stationId,
        stationName: stationName,
      );
    }

    if (widget.onNavigateToStation != null) {
      widget.onNavigateToStation!(station);
    } else {
      // Fallback to old navigation method if callback not provided
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ListScreen(),
          settings: RouteSettings(arguments: {
            'showStationDetails': true,
            'stationId': navigationId,
          }),
        ),
      );
    }
  }

  List<Marker> _markers = [];
  List<GasStation> _gasStations = [];
  List<GasStation> _filteredGasStations = [];

  String _searchQuery = '';
  String _selectedFuelType = 'Regular';
  String _selectedPriceFilter = 'All'; // All / Cheap / Mid / Expensive
  static const double _cheapPriceUpperBound = 52.0;
  static const double _expensivePriceLowerBound = 65.0;
  FuelTypeFilter?
      _selectedFuelTypeFilter; // Filter stations by available fuel types
  bool _showFilters = false;

  double _iconScale = 1.1; // default slightly larger

  final NavigationService _navigationService = NavigationService();

  bool _isNavigating = false;
  bool _voiceEnabled = true;

  double _minPrice = double.infinity;
  double _maxPrice = -double.infinity;

  // Ratings cache: stationId => { userId: { name, rating, comment } }
  Map<String, Map<String, Map<String, dynamic>>> _ratings = {};

  // Real-time subscriptions
  StreamSubscription<QuerySnapshot>? _realtimePriceSubscription;
  // StreamSubscription<QuerySnapshot>? _realtimeRatingsSubscription; // Removed for performance

  @override
  void initState() {
    super.initState();
    _initializeAndLoadStations();
    _navigationService.addListener(_onNavigationUpdate);
    _setupRealtimeListeners();
  }

  @override
  void dispose() {
    _navigationService.removeListener(_onNavigationUpdate);
    _realtimePriceSubscription?.cancel();
    // _realtimeRatingsSubscription?.cancel(); // Removed for performance
    super.dispose();
  }

  void _onNavigationUpdate() {
    if (mounted) {
      setState(() {
        _isNavigating = _navigationService.isNavigating;
      });
    }
  }

  Future<void> _initializeAndLoadStations() async {
    try {
      // Removed call to GasStationService.fetchAndCacheGasStations() as we now load from Firestore directly
      await _loadGasStations();
    } catch (e) {
      debugPrint('Error initializing gas stations: $e');
      await _loadGasStations();
    }
  }

  @override
  void didUpdateWidget(MapTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assignedStations != widget.assignedStations) {
      _initializeAndLoadStations();
    }
  }

  Future<void> _loadGasStations() async {
    try {
      // Load only approved stations from Firestore
      // Map starts empty - stations only appear when owners register and are approved
      final registeredStations = await _loadRegisteredStations();
      _gasStations = registeredStations;

      // COMMENTED OUT: OSM stations with randomized prices
      // Gas stations should only appear when owners register and are approved
      // final osmStations = await _loadOpenStreetMapStations();
      // _gasStations.addAll(osmStations);

      _filterAndSearch();
    } catch (e) {
      debugPrint('Error loading gas stations: $e');
    }
  }

  /// Load registered gas stations from Firestore with real prices and ratings
  /// Only shows stations from owners with approvalStatus = 'approved'
  /// Uses ownerApprovalStatus field stored in gas_station document
  Future<List<GasStation>> _loadRegisteredStations() async {
    try {
      // Get all stations from Firestore
      final firestoreStations = await FirestoreService.getAllGasStations();

      // Filter stations to include those from approved or pending owners
      // Use ownerApprovalStatus field stored in gas_station document (avoids permission issues)
      // Show stations immediately after registration (pending) and after approval
      final approvedStations = firestoreStations.where((stationMap) {
        final ownerApprovalStatus =
            stationMap['ownerApprovalStatus'] as String? ?? 'pending';
        // Show stations from approved or pending owners (not rejected)
        return ownerApprovalStatus == 'approved' ||
            ownerApprovalStatus == 'pending';
      }).toList();

      // Convert Firestore data to GasStation objects
      final registeredStations = approvedStations.map((stationMap) {
        // Ensure the station has an ID
        stationMap['id'] = stationMap['id'] ?? '';

        debugPrint('[MAP] Processing station: ${stationMap['id']}');
        debugPrint('[MAP] Station name: ${stationMap['name']}');
        debugPrint('[MAP] Station data keys: ${stationMap.keys.toList()}');
        debugPrint('[MAP] Has position: ${stationMap.containsKey('position')}');
        debugPrint('[MAP] Has geoPoint: ${stationMap.containsKey('geoPoint')}');
        debugPrint('[MAP] Position value: ${stationMap['position']}');
        debugPrint('[MAP] GeoPoint value: ${stationMap['geoPoint']}');

        // Convert to GasStation object
        final station = GasStation.fromMap(stationMap);

        debugPrint(
            '[MAP] Station position after conversion: ${station.position.latitude}, ${station.position.longitude}');

        // Validate position (should not be 0,0 unless it's actually at that location)
        if (station.position.latitude == 0.0 &&
            station.position.longitude == 0.0) {
          debugPrint(
              '[MAP] WARNING: Station ${stationMap['id']} has invalid position (0,0)');
        }

        // Load ratings for this station - REMOVED for performance (N+1 issue)
        // _loadStationRatings(station.id ?? '');

        return station;
      }).toList();

      debugPrint(
          '[MAP] Loaded ${registeredStations.length} approved/pending stations from Firestore');
      debugPrint(
          '[MAP] Total stations after conversion: ${registeredStations.length}');
      return registeredStations;
    } catch (e) {
      debugPrint('Error loading registered stations: $e');
      return [];
    }
  }

  /// Load ratings for a specific station
  Future<void> _loadStationRatings(String stationId) async {
    if (stationId.isEmpty) return;

    try {
      final ratingsSnapshot =
          await FirestoreService.getStationRatingsFromGlobalCollection(
                  stationId)
              .first;
      final Map<String, Map<String, dynamic>> stationRatings = {};

      for (final doc in ratingsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final userId = data['userId'] as String? ?? '';
        if (userId.isNotEmpty) {
          stationRatings[userId] = {
            'name': data['userName'] ?? userId,
            'rating': (data['rating'] as num?)?.toDouble() ?? 0.0,
            'comment': data['comment'] ?? '',
          };
        }
      }

      _ratings[stationId] = stationRatings;
    } catch (e) {
      debugPrint('Error loading ratings for station $stationId: $e');
    }
  }

  /// Calculate average rating for a station
  double _calculateAverageRating(String stationId) {
    final stationRatings = _ratings[stationId];
    if (stationRatings == null || stationRatings.isEmpty) return 0.0;

    double sum = 0.0;
    int count = 0;
    stationRatings.forEach((userId, data) {
      final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
      if (rating > 0) {
        sum += rating;
        count++;
      }
    });

    return count == 0 ? 0.0 : sum / count;
  }

  /// Setup real-time listeners for prices and ratings
  void _setupRealtimeListeners() {
    // Listen to gas_stations collection for real-time price updates
    // Only listening to prices as this is critical, but we could even remove this if needed
    _realtimePriceSubscription = FirebaseFirestore.instance
        .collection('gas_stations')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        _updateStationsFromSnapshot(snapshot);
      }
    });

    // REMOVED: Listen to station_ratings collection for real-time rating updates
    // This causes massive reads and lag. Ratings will be loaded on demand.
  }

  /// Update stations from Firestore snapshot
  void _updateStationsFromSnapshot(QuerySnapshot snapshot) {
    try {
      final updatedStations = <GasStation>[];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;

        // Convert to GasStation object
        final station = GasStation.fromMap(data);
        updatedStations.add(station);
      }

      // Update the stations list
      _gasStations = updatedStations;
      _filterAndSearch();

      debugPrint(
          'Updated ${updatedStations.length} stations from real-time data');
    } catch (e) {
      debugPrint('Error updating stations from snapshot: $e');
    }
  }

  // REMOVED: _updateRatingsFromSnapshot to prevent global rating updates

  /// Starts voice navigation to the station's coordinates (uses current location internally).
  void _startNavigation(GasStation station) async {
    try {
      await _navigationService.initializeVoiceNavigation();
      await _navigationService.startNavigation(station.position);

      // Calculate distance and estimated arrival time
      if (_navigationService.currentLocation != null) {
        final currentLatLng = LatLng(
          _navigationService.currentLocation!.latitude!,
          _navigationService.currentLocation!.longitude!,
        );
        final distanceKm = _calculateDistance(currentLatLng, station.position);
        const averageSpeedKmh = 40.0; // Assume average speed 40 km/h
        final estimatedTimeHours = distanceKm / averageSpeedKmh;
        final estimatedDuration =
            Duration(minutes: (estimatedTimeHours * 60).round());

        setState(() {
          _distanceToStationKm = distanceKm;
          _estimatedArrivalTime = estimatedDuration;
          _isNavigating = true;
          _voiceEnabled = true;
          _showNavigationDashboard = true;
          _nextInstruction = _navigationService.nextTurn;

          // Disable lock initially so user can see the full route overview
          _isMapLocked = false;

          _locationUpdateTimer?.cancel();
          _locationUpdateTimer =
              Timer.periodic(const Duration(seconds: 1), (timer) {
            if (_isMapLocked && _navigationService.currentLocation != null) {
              _mapController.move(
                LatLng(
                  _navigationService.currentLocation!.latitude!,
                  _navigationService.currentLocation!.longitude!,
                ),
                _mapController.camera.zoom,
              );
            }
          });

          // Fit bounds to show whole route (Current Location + Destination)
          final bounds = LatLngBounds(currentLatLng, station.position);
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(50.0),
            ),
          );
        });
      } else {
        setState(() {
          _distanceToStationKm = null;
          _estimatedArrivalTime = null;
          _isNavigating = true;
          _voiceEnabled = true;
          _showNavigationDashboard = true;
          _nextInstruction = _navigationService.nextTurn;
        });
      }
    } catch (e) {
      debugPrint('Error starting navigation: $e');
    }
  }

  void _stopNavigation() {
    _navigationService.stopNavigation();
    setState(() {
      _isNavigating = false;
      _showNavigationDashboard = false;
    });
  }

  void _toggleVoiceNavigation() {
    setState(() {
      _voiceEnabled = !_voiceEnabled;
    });
    _navigationService.setVoiceEnabled(_voiceEnabled);
  }

  // COMMENTED OUT: Loading OSM stations with randomized prices
  // Gas stations should only appear when owners register and are approved
  // Map starts empty - stations only appear after owner registration and approval
  /*
  Future<List<GasStation>> _loadOpenStreetMapStations() async {
    // keep your bbox or make configurable
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

      // Get existing registered station positions to avoid duplicates
      final registeredPositions = _gasStations.map((station) => station.position).toList();

      for (final el in elems) {
        final id = 'osm_${el['id']}';
        final tags = el['tags'] ?? <String, dynamic>{};
        final name = tags['name'] ?? 'Gas Station';
        final brand = tags['brand'] ?? 'Unknown';
        final address = tags['addr:full'] ?? 'Valencia City, Bukidnon';
        final lat = el['lat'] ?? el['center']['lat'];
        final lon = el['lon'] ?? el['center']['lon'];
        final position = LatLng(lat, lon);

        // Check if this position is already covered by a registered station
        bool isNearRegisteredStation = registeredPositions.any((registeredPos) {
          final distance = _calculateDistance(position, registeredPos);
          return distance < 0.001; // ~100 meters threshold
        });

        // Only add OSM station if it's not near a registered station
        if (!isNearRegisteredStation) {
          // COMMENTED OUT: Randomizer for unregistered OSM stations
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
      }

      debugPrint('Loaded ${stations.length} OSM stations (unregistered) with randomized prices');
      return stations;
    } catch (e) {
      debugPrint('Error loading OSM stations: $e');
      return [];
    }
  }
  */

  /// Calculate distance between two LatLng points in kilometers
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // Earth's radius in kilometers
    final double lat1Rad = point1.latitude * (math.pi / 180);
    final double lat2Rad = point2.latitude * (math.pi / 180);
    final double deltaLat =
        (point2.latitude - point1.latitude) * (math.pi / 180);
    final double deltaLon =
        (point2.longitude - point1.longitude) * (math.pi / 180);

    final double a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  void _filterAndSearch() {
    debugPrint(
        '[MAP] _filterAndSearch: Starting with ${_gasStations.length} stations');
    List<GasStation> filtered = List<GasStation>.from(_gasStations);

    // Apply fuel type filter (filter stations by available fuel types)
    if (_selectedFuelTypeFilter != null &&
        _selectedFuelTypeFilter != FuelTypeFilter.all) {
      filtered = filtered.where((station) {
        return _stationMatchesFuelTypeFilter(station, _selectedFuelTypeFilter!);
      }).toList();
    }

    // Apply price filter
    // Allow stations without prices to show (they appear as grey markers)
    if (_selectedPriceFilter != 'All') {
      final priceRanges = _getPriceRanges();
      filtered = filtered.where((station) {
        final price = _getStationPrice(station, _selectedFuelType);
        // If station has no price, still show it (don't filter out)
        if (price == null) return true;

        switch (_selectedPriceFilter) {
          case 'Cheap':
            return price < priceRanges['cheap']!;
          case 'Mid':
            return price >= priceRanges['cheap']! &&
                price <= priceRanges['expensive']!;
          case 'Expensive':
            return price > priceRanges['expensive']!;
          default:
            return true;
        }
      }).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((station) {
        final name = (station.name ?? '').toLowerCase();
        final brand = (station.brand ?? '').toLowerCase();

        // Match fuel type names (e.g. searching "diesel" shows stations with diesel)
        final fuelTypesMatch = (station.prices?.keys ?? [])
            .any((k) => k.toLowerCase().contains(q));

        // Match performance type labels/descriptions
        bool performanceMatch = false;
        if (station.fuelPerformance != null) {
          performanceMatch = station.fuelPerformance!.values.any((perf) {
            final type = (perf['type'] as String? ?? '').toLowerCase();
            final label = (perf['label'] as String? ?? '').toLowerCase();
            final desc = (perf['description'] as String? ?? '').toLowerCase();
            return type.contains(q) || label.contains(q) || desc.contains(q);
          });
        }

        final priceMatch =
            (station.prices?.values ?? []).any((p) => p.toString().contains(q));

        return name.contains(q) ||
            brand.contains(q) ||
            fuelTypesMatch ||
            performanceMatch ||
            priceMatch;
      }).toList();
    }

    _filteredGasStations = filtered;
    debugPrint(
        '[MAP] _filterAndSearch: After filtering, ${_filteredGasStations.length} stations remain');
    _createMarkers();
  }

  // Check if a station matches the selected fuel type filter
  // Allow stations without prices to show (they appear as grey markers)
  bool _stationMatchesFuelTypeFilter(
      GasStation station, FuelTypeFilter filter) {
    // If station has no prices, still show it (don't filter out)
    if (station.prices == null || station.prices!.isEmpty) return true;

    // Normalize fuel type keys to lowercase for comparison
    final availableFuelTypes =
        station.prices!.keys.map((k) => k.toLowerCase()).toSet();

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

  @override
  Widget build(BuildContext context) {
    // Google-Maps-like look: floating search card over map, rounded corners, subtle shadows
    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zoom In Button
          FloatingActionButton(
            heroTag: 'zoomIn',
            mini: true,
            onPressed: () {
              final currentZoom = _mapController.camera.zoom;
              _mapController.move(
                _mapController.camera.center,
                currentZoom + 1,
              );
            },
            tooltip: 'Zoom In',
            child: const Icon(Icons.add, size: 20),
          ),
          const SizedBox(height: 8),

          // Zoom Out Button
          FloatingActionButton(
            heroTag: 'zoomOut',
            mini: true,
            onPressed: () {
              final currentZoom = _mapController.camera.zoom;
              _mapController.move(
                _mapController.camera.center,
                currentZoom - 1,
              );
            },
            tooltip: 'Zoom Out',
            child: const Icon(Icons.remove, size: 20),
          ),
          const SizedBox(height: 8),

          // Go to Current Location Button
          FloatingActionButton(
            heroTag: 'location',
            mini: true,
            onPressed: () {
              if (_navigationService.currentLocation != null) {
                _mapController.move(
                  LatLng(
                    _navigationService.currentLocation!.latitude!,
                    _navigationService.currentLocation!.longitude!,
                  ),
                  16.0,
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Location not available')),
                );
              }
            },
            tooltip: 'Go to My Location',
            child: const Icon(Icons.my_location, size: 20),
          ),
          const SizedBox(height: 8),

          // Lock/Unlock Navigation Button
          FloatingActionButton(
            heroTag: 'lock',
            onPressed: () {
              setState(() {
                _isMapLocked = !_isMapLocked;
              });
            },
            tooltip: _isMapLocked ? 'Unlock Map' : 'Lock to Location',
            child: Icon(_isMapLocked ? Icons.lock : Icons.lock_open),
          ),
          const SizedBox(height: 8),

          // Marker Size Button
          FloatingActionButton(
            heroTag: 'size',
            mini: true,
            onPressed: () async {
              // small bottom sheet to adjust icon size
              final newScale = await showModalBottomSheet<double>(
                context: context,
                builder: (context) {
                  double tmp = _iconScale;
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Marker size'),
                        StatefulBuilder(
                          builder: (context, setStateSB) {
                            return Slider(
                              min: 0.7,
                              max: 1.6,
                              value: tmp,
                              onChanged: (v) {
                                setStateSB(() => tmp = v);
                              },
                            );
                          },
                        ),
                        ElevatedButton(
                          child: const Text('Apply'),
                          onPressed: () => Navigator.of(context).pop(tmp),
                        )
                      ],
                    ),
                  );
                },
              );
              if (newScale != null) {
                setState(() => _iconScale = newScale);
                _createMarkers();
              }
            },
            child: const Icon(Icons.photo_size_select_large, size: 20),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map (always visible, full screen)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _getInitialMapCenter(),
              initialZoom: 14.5,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.fuelgo.app',
              ),
              MarkerLayer(markers: _markers),
              if (_isNavigating && _navigationService.polylines.isNotEmpty)
                PolylineLayer(polylines: _navigationService.polylines),
              // Show current location marker (always visible when location is available)
              if (_navigationService.currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _navigationService.currentLocation!.latitude!,
                        _navigationService.currentLocation!.longitude!,
                      ),
                      width: 40,
                      height: 40,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer pulsing circle
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          // Inner solid circle
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          // Direction indicator (optional, shows when navigating)
                          if (_isNavigating)
                            Icon(
                              Icons.navigation,
                              color: Colors.white,
                              size: 12,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Floating search/filter card (top center) - Google Maps style
          Positioned(
            left: 14,
            right: 14,
            top: 40,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.search, color: Colors.black54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Search station or Fuel Type',
                              border: InputBorder.none,
                            ),
                            onChanged: (value) {
                              setState(() => _searchQuery = value);
                              _filterAndSearch();
                            },
                          ),
                        ),
                        IconButton(
                          icon: Icon(_showFilters
                              ? Icons.filter_list
                              : Icons.filter_list_outlined),
                          onPressed: () {
                            setState(() => _showFilters = !_showFilters);
                          },
                        ),
                      ],
                    ),
                    if (_showFilters) const SizedBox(height: 8),
                    if (_showFilters)
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _fuelTypeChips()),
                              const SizedBox(width: 8),
                              _priceFilterDropdown(),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Fuel type filter dropdown (filter stations by available fuel types)
                          DropdownButtonFormField<FuelTypeFilter?>(
                            value: _selectedFuelTypeFilter,
                            decoration: InputDecoration(
                              labelText: 'Filter by Available Fuel Types',
                              prefixIcon:
                                  const Icon(Icons.filter_alt, size: 18),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
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
                                _filterAndSearch();
                              });
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Map header legend (bottom-left)
          Positioned(
            left: 14,
            bottom: 18,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _LegendItem(color: Colors.green, label: 'Cheap'),
                        const SizedBox(width: 8),
                        _LegendItem(
                            color: Colors.yellow.shade600, label: 'Mid'),
                        const SizedBox(width: 8),
                        _LegendItem(color: Colors.red, label: 'Expensive'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showNavigationDashboard) _buildNavigationDashboard(),
          // Minimized navigation header - shows when dashboard is hidden
          if (_isNavigating && !_showNavigationDashboard)
            Positioned(
              top: _showFilters ? 140 : 100,
              left: 14,
              right: 14,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
                child: InkWell(
                  onTap: () => setState(() => _showNavigationDashboard = true),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.navigation,
                            color: Colors.blue.shade600, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Navigating to Gas Station',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Maximize button
                        Icon(Icons.keyboard_arrow_down,
                            color: Colors.blue.shade600, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavigationDashboard() {
    return Positioned(
      top: _showFilters ? 140 : 100, // Adjust based on filter visibility
      left: 14,
      right: 14,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with destination info
              // Header with destination info
              Row(
                children: [
                  Icon(Icons.navigation, color: Colors.blue.shade600, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Navigating to Gas Station',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Minimize/Maximize button
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                    onPressed: () =>
                        setState(() => _showNavigationDashboard = false),
                    tooltip: 'Minimize',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const Divider(),

              // Time and Distance Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _DashboardItem(
                    icon: Icons.schedule,
                    label: 'ETA',
                    value: _formatETA(
                        _trafficAdjustedTime ?? _estimatedArrivalTime),
                    color: _getTrafficColor(_trafficLevel),
                  ),
                  _DashboardItem(
                    icon: Icons.straighten,
                    label: 'Distance',
                    value:
                        '${_distanceToStationKm?.toStringAsFixed(1) ?? '0'} km',
                    color: Colors.blue,
                  ),
                  _DashboardItem(
                    icon: Icons.speed,
                    label: 'Speed',
                    value: '${_currentSpeed.toStringAsFixed(0)} km/h',
                    color: Colors.green,
                  ),
                ],
              ),

              // Traffic indicator
              if (_trafficLevel > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getTrafficColor(_trafficLevel).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getTrafficColor(_trafficLevel)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getTrafficIcon(_trafficLevel),
                          size: 16, color: _getTrafficColor(_trafficLevel)),
                      const SizedBox(width: 6),
                      Text(
                        _getTrafficText(_trafficLevel),
                        style: TextStyle(
                          color: _getTrafficColor(_trafficLevel),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Next instruction
              if (_nextInstruction.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    _nextInstruction,
                    style: TextStyle(color: Colors.blue.shade700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Fuel type selection as chips
  Widget _fuelTypeChips() {
    final types = ['Regular', 'Premium', 'Diesel'];
    return Wrap(
      spacing: 8,
      children: types.map((t) {
        final selected = _selectedFuelType == t;
        return ChoiceChip(
          label: Text(t),
          selected: selected,
          onSelected: (v) {
            setState(() {
              _selectedFuelType = t;
            });
            _filterAndSearch();
          },
        );
      }).toList(),
    );
  }

  /// Price filter dropdown with colored dots
  Widget _priceFilterDropdown() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedPriceFilter,
        items: ['All', 'Cheap', 'Mid', 'Expensive'].map((value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Row(
              children: [
                if (value != 'All')
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: _getColorForPriceFilterName(value),
                          shape: BoxShape.circle)),
                if (value == 'All') const Icon(Icons.tune, size: 18),
                const SizedBox(width: 8),
                Text(value),
              ],
            ),
          );
        }).toList(),
        onChanged: (String? v) {
          setState(() {
            _selectedPriceFilter = v ?? 'All';
          });
          _filterAndSearch();
        },
      ),
    );
  }

  Color _getColorForPriceFilterName(String name) {
    switch (name) {
      case 'Cheap':
        return Colors.green;
      case 'Mid':
        return Colors.yellow.shade700;
      case 'Expensive':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Map<String, double> _getPriceRanges() {
    return {
      'cheap': _cheapPriceUpperBound,
      'expensive': _expensivePriceLowerBound,
    };
  }

  double? _getStationPrice(GasStation station, String fuelType) {
    if (station.prices == null) return null;
    final normalizedKey = fuelType.toLowerCase();
    return station.prices![normalizedKey];
  }

  // Color coding: Green = cheap, Yellow = mid, Red = expensive
  Color _colorForPriceWithRanges(double price, double min, double max) {
    if (price <= min) return Colors.green;
    if (price >= max) return Colors.red;
    return Colors.yellow.shade600;
  }

  /// Create markers for the filtered list. Each marker color is computed from that station's price distribution.
  void _createMarkers() {
    debugPrint(
        '[MAP] Creating markers for ${_filteredGasStations.length} filtered stations');

    double minPrice = double.infinity;
    double maxPrice = -double.infinity;

    // Calculate min/max prices among filtered stations for the selected fuel type
    for (var station in _filteredGasStations) {
      final price = _getStationPrice(station, _selectedFuelType);
      if (price != null) {
        if (price < minPrice) minPrice = price;
        if (price > maxPrice) maxPrice = price;
      }
    }

    _minPrice = minPrice;
    _maxPrice = maxPrice;

    // If only one price point or no prices, avoid red logic by making them same or separate
    // Actually if min == max, all will be green (lowest) based on _colorForPriceWithRanges

    _markers = _filteredGasStations.where((station) {
      // Filter out stations with invalid positions (0,0) - both lat and lng must be non-zero
      final isValidPosition = !(station.position.latitude == 0.0 &&
          station.position.longitude == 0.0);
      if (!isValidPosition) {
        debugPrint(
            '[MAP] Skipping station ${station.id} - invalid position (0,0)');
      }
      return isValidPosition;
    }).map((station) {
      final price = _getStationPrice(station, _selectedFuelType);
      // Use cached averageRating directly instead of recalculating from _ratings map
      final rating = station.averageRating ?? 0.0;

      final markerColor = (price != null)
          ? _colorForPriceWithRanges(price, minPrice, maxPrice)
          : Colors.grey;

      debugPrint(
          '[MAP] Creating marker for station: ${station.id}, name: ${station.name}');
      debugPrint(
          '[MAP] Position: ${station.position.latitude}, ${station.position.longitude}');
      debugPrint('[MAP] Marker color: $markerColor');

      return Marker(
        point: station.position,
        width: 56 * _iconScale,
        height: 56 * _iconScale,
        // <-- use `child:` (some flutter_map versions expect child rather than builder)
        child: RepaintBoundary(
          child: _AnimatedGasStationMarker(
            station: station,
            markerColor: markerColor,
            price: price,
            rating: rating,
            isOpen: station.isOpen,
            iconSize: _iconScale,
            isRegistered: station.isOwnerCreated ??
                false, // Indicate if station is registered
            onTap: () => _showStationModal(station),
          ),
        ),
      );
    }).toList();

    debugPrint('[MAP] Created ${_markers.length} markers');
    if (mounted) setState(() {});
  }

  LatLng _getInitialMapCenter() {
    if (_filteredGasStations.isNotEmpty) {
      return _filteredGasStations[0].position;
    }
    if (_gasStations.isNotEmpty) return _gasStations[0].position;
    // Use current location if available
    if (_navigationService.currentLocation != null) {
      return LatLng(
        _navigationService.currentLocation!.latitude ?? 0.0,
        _navigationService.currentLocation!.longitude ?? 0.0,
      );
    }
    // Default center: Valencia City, Bukidnon, Philippines
    // This provides a reasonable default location for the map when no stations or user location is available
    return const LatLng(7.9055, 125.0908);
  }

  // ------------- modal bottom sheet to show station details -------------
  void _showStationModal(GasStation station) {
    // Track station click interaction
    final stationId = station.id ?? '';
    final stationName = station.name ?? 'Unknown Station';
    if (stationId.isNotEmpty) {
      UserInteractionService.trackStationClick(
        stationId: stationId,
        stationName: stationName,
      );

      // Lazy load ratings when opening the modal
      _loadStationRatings(stationId).then((_) {
        if (mounted) setState(() {});
      });
    }

    // Track price view if price is available
    final price = _getStationPrice(station, _selectedFuelType);
    if (price != null && stationId.isNotEmpty) {
      UserInteractionService.trackPriceView(
        stationId: stationId,
        stationName: stationName,
        fuelType: _selectedFuelType.toLowerCase(),
        price: price,
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        // Calculate additional padding when navigation is active
        final additionalPadding = _isNavigating ? 100.0 : 0.0;

        return Padding(
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(context).viewInsets.bottom + additionalPadding,
          ),
          child: SafeArea(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                station.name ?? 'Gas Station',
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              if (station.isOwnerCreated == true) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.green.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified,
                                          size: 12,
                                          color: Colors.green.shade700),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Registered Station',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            _toggleVoiceNavigation();
                          },
                          icon: Icon(_voiceEnabled
                              ? Icons.volume_up
                              : Icons.volume_off),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (station.brand != null)
                      Text('${station.brand}',
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black54)),
                    const SizedBox(height: 6),
                    Text(station.address ?? '',
                        style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (price != null)
                          Row(
                            children: [
                              const Icon(Icons.local_gas_station, size: 18),
                              const SizedBox(width: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '$_selectedFuelType: ₱${price.toStringAsFixed(2)}',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: _colorForPriceWithRanges(
                                              price, _minPrice, _maxPrice))),
                                  if (station.fuelPerformance != null &&
                                      station.fuelPerformance![_selectedFuelType
                                              .toLowerCase()] !=
                                          null) ...[
                                    Text(
                                      station.fuelPerformance![_selectedFuelType
                                              .toLowerCase()]!['label'] ??
                                          '',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                  if (station.hasPriceReduction(
                                      _selectedFuelType.toLowerCase()))
                                    Text(
                                      '₱${(price + station.getReductionAmount(_selectedFuelType.toLowerCase())).toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          )
                        else
                          Row(children: const [
                            Icon(Icons.local_gas_station, size: 18),
                            SizedBox(width: 6),
                            Text('Price not available')
                          ]),
                        Row(
                          children: [
                            const Icon(Icons.star,
                                size: 16, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(_calculateAverageRating(station.id ?? '')
                                .toStringAsFixed(1)),
                          ],
                        ),
                      ],
                    ),
                    // navigation status indicator when active
                    if (_isNavigating) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
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
                                Icon(Icons.navigation,
                                    size: 16, color: Colors.blue.shade600),
                                const SizedBox(width: 8),
                                Text(
                                  'Navigation Active',
                                  style: TextStyle(
                                    color: Colors.blue.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (_distanceToStationKm != null &&
                                _estimatedArrivalTime != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Distance: ${_distanceToStationKm!.toStringAsFixed(2)} km',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              Text(
                                'Estimated Arrival: ${_estimatedArrivalTime!.inMinutes} min',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_isNavigating)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _stopNavigation();
                              },
                              icon: const Icon(Icons.stop),
                              label: const Text('Stop Navigation'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                elevation: 6,
                                shadowColor: Colors.redAccent.withOpacity(0.5),
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _startNavigation(station);
                              },
                              icon: const Icon(Icons.navigation),
                              label: const Text('Start Navigation'),
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _navigateToGasStationDetail(station);
                                },
                                icon: const Icon(Icons.info_outline, size: 18),
                                label: const Text('View Details'),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  _mapController.move(station.position, 16.0);
                                },
                                icon: const Icon(Icons.center_focus_strong,
                                    size: 18),
                                label: const Text('Center'),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Close'),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatETA(Duration? duration) {
    if (duration == null) return '--:--';
    final now = DateTime.now().add(duration);
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Color _getTrafficColor(int level) {
    switch (level) {
      case 1:
        return Colors.yellow.shade700;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.green;
    }
  }

  IconData _getTrafficIcon(int level) {
    switch (level) {
      case 1:
        return Icons.info;
      case 2:
        return Icons.warning;
      case 3:
        return Icons.error;
      default:
        return Icons.check_circle;
    }
  }

  String _getTrafficText(int level) {
    switch (level) {
      case 1:
        return 'Light traffic';
      case 2:
        return 'Moderate traffic - delays expected';
      case 3:
        return 'Heavy traffic - consider alternative route';
      default:
        return 'Clear roads';
    }
  }

  void _showAlternativeRoutes() {
    final alternatives = _navigationService.alternativeRoutes;

    if (alternatives.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No alternative routes found. Try a longer route or different destination.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.alt_route, color: Colors.blue),
                  const SizedBox(width: 12),
                  const Text(
                    'Alternative Routes',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Select an alternative route:',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),

              // Current route (main route)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.navigation, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Route',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${_navigationService.distance} • ${_navigationService.duration}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Alternative routes list
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: alternatives.length,
                  itemBuilder: (context, index) {
                    final alt = alternatives[index];
                    final distance = alt['distance'] as String;
                    final duration = alt['duration'] as String;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _navigationService
                              .switchToAlternativeRoute(index);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Switched to alternative route ${index + 1}')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Alternative Route ${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '$distance • $duration',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios,
                                size: 16, color: Colors.grey),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------- Keep your animated marker classes ----------------
class _AnimatedGasStationMarker extends StatefulWidget {
  final GasStation station;
  final Color markerColor;
  final double? price;
  final double rating;
  final bool isOpen;
  final double iconSize;
  final bool isRegistered;
  final VoidCallback onTap;

  const _AnimatedGasStationMarker({
    required this.station,
    required this.markerColor,
    required this.price,
    required this.rating,
    required this.isOpen,
    required this.iconSize,
    required this.isRegistered,
    required this.onTap,
  });

  @override
  State<_AnimatedGasStationMarker> createState() =>
      _AnimatedGasStationMarkerState();
}

class _AnimatedGasStationMarkerState extends State<_AnimatedGasStationMarker>
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

  // Color coding: Green = cheap, Yellow = medium, Red = expensive
  // Simplified: Use the marker color for badge (already computed from price ranges in parent)
  Color _getPriceBadgeColor(double price) {
    // Use the marker color which is already based on price ranges
    // This ensures consistency with the marker border color
    return widget.markerColor;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.iconSize;
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
                          width: widget.isRegistered
                              ? 4 * s
                              : 3 * s, // Thicker border for registered stations
                        ),
                      ),
                      child: Icon(
                        widget.isRegistered
                            ? Icons.local_gas_station
                            : Icons.local_gas_station_outlined,
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
                        padding: EdgeInsets.symmetric(
                            horizontal: 6 * s, vertical: 3 * s),
                        decoration: BoxDecoration(
                          color: _getPriceBadgeColor(widget.price!),
                          borderRadius: BorderRadius.circular(10 * s),
                          border:
                              Border.all(color: Colors.white, width: 1.2 * s),
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
                  if (widget.station.brand != null &&
                      widget.station.brand!.isNotEmpty)
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
                        padding: EdgeInsets.symmetric(
                            horizontal: 4 * s, vertical: 2 * s),
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
  final IconData? icon;

  const _LegendItem({
    required this.color,
    required this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
        ] else
          Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                color: Colors.black87,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _DashboardItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DashboardItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
