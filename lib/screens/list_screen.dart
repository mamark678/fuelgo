  // list_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gas_station.dart' as models;
import '../models/voucher.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gas_station_service.dart' as services;
import '../services/navigation_service.dart';
import '../services/user_preferences_service.dart';
import '../services/user_service_fixed.dart';
import '../widgets/price_reduction_widget.dart';

class ListScreen extends StatefulWidget {
  const ListScreen({Key? key}) : super(key: key);

  @override
  ListScreenState createState() => ListScreenState();
}

class ListScreenState extends State<ListScreen> {
  final Location _locationService = Location();
  final NavigationService _navigationService = NavigationService();
  final UserPreferencesService _prefsService = UserPreferencesService();
  String _selectedFuelType = 'Regular';
  String _selectedBrand = 'All';
  String _sortBy = 'Distance';
  String _searchQuery = '';
  bool _showFilters = false;
  bool _disposed = false;
  List<models.GasStation> _filteredGasStations = [];
  List<models.GasStation> _gasStations = [];

  // Ratings data structure:
  // stationId => { userId: { name, rating, comment } }
  Map<String, Map<String, Map<String, dynamic>>> _ratings = {};

  StreamSubscription<LocationData>? _locationSubscription;
  StreamSubscription<QuerySnapshot>? _ratingsSubscription;
  StreamSubscription<QuerySnapshot>? _realtimePriceSubscription;
  StreamSubscription<User?>? _authStateSubscription;

  Map<String, dynamic>? _arguments;

  @override
  void initState() {
    super.initState();
    _selectedFuelType = _prefsService.preferredFuelType;
    _prefsService.addListener(_onPrefsChanged);
    _requestPermissionAndFetchLocation();

    // Load local ratings first, then start listeners and load stations
    _loadRatingsFromStorage().then((_) {
      _loadGasStations().then((_) {
        _setupRatingsRealtimeListener(); // keep _ratings in sync with Firestore
        _setupRealtimePriceListener(); // existing real-time gas_stations listener

        // Check if we need to automatically show station details AFTER stations are loaded
        _checkAndShowStationDetails();
      });
    });

    _navigationService.addListener(_onNavigationChanged);

    // Listen to device location updates
    _locationSubscription = _locationService.onLocationChanged.listen((loc) {
      _navigationService.updateLocation(loc);
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _arguments = args;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _prefsService.removeListener(_onPrefsChanged);
    _navigationService.removeListener(_onNavigationChanged);
    _locationSubscription?.cancel();
    _ratingsSubscription?.cancel();
    _realtimePriceSubscription?.cancel();
    super.dispose();
  }

  void _onPrefsChanged() {
    if (_selectedFuelType != _prefsService.preferredFuelType) {
      setState(() {
        _selectedFuelType = _prefsService.preferredFuelType;
      });
    } else {
      setState(() {});
    }
  }

  void _onNavigationChanged() {
    if (_disposed || !mounted) return;
    setState(() {});
  }

  void _checkAndShowStationDetails() {
    if (_arguments != null && _arguments!['showStationDetails'] == true) {
      final stationId = _arguments!['stationId'];
      if (stationId != null && stationId is String && stationId.isNotEmpty) {
        // Wait for stations to be loaded before attempting to find the station
        if (_gasStations.isEmpty) {
          // If stations aren't loaded yet, set up a one-time listener to check again
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _gasStations.isNotEmpty) {
              _findAndShowStationDetails(stationId.toString());
            }
          });
        } else {
          _findAndShowStationDetails(stationId.toString());
        }
      }
    }
  }

  void showStationDetails(String stationId) {
    _findAndShowStationDetails(stationId);
  }

  void _findAndShowStationDetails(String stationId) async {
    // First, check if the station object was passed directly in arguments
    if (_arguments != null && _arguments!['station'] != null) {
      final station = _arguments!['station'] as models.GasStation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showGasStationDetails(station);
          // Clear the arguments to prevent showing again on rebuild
          _arguments!['showStationDetails'] = false;
        }
      });
      return;
    }

    // If station object wasn't passed, try to find station by ID/name in the list
    models.GasStation? foundStation = _findStationInList(stationId);

    // If not found locally, try to refresh the gas stations from Firebase
    if (foundStation == null || foundStation.id == null || foundStation.id!.isEmpty) {
      debugPrint('Station not found locally, refreshing from Firebase...');
      try {
        await _loadGasStations(); // Refresh the stations list
        foundStation = _findStationInList(stationId); // Try again
      } catch (e) {
        debugPrint('Error refreshing stations: $e');
      }
    }

    // Show the station details if found
    if (foundStation != null && foundStation.id != null && foundStation.id!.isNotEmpty) {
      // Check if this station is registered in Firestore (has owner data)
      final isRegistered = await _checkIfStationIsRegistered(foundStation.id!);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showGasStationDetails(foundStation!, isRegistered: isRegistered);
          // Clear the arguments to prevent showing again on rebuild
          if (_arguments != null) {
            _arguments!['showStationDetails'] = false;
          }
        }
      });
    } else {
      // Station not found - show error message with more details
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gas station not found: $stationId. The station may not exist or there may be a connection issue.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () => _findAndShowStationDetails(stationId),
              ),
            ),
          );
        }
      });
    }
  }

  Future<bool> _checkIfStationIsRegistered(String stationId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('gas_stations').doc(stationId).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('ownerId') && (data['ownerId'] as String).isNotEmpty) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error checking station registration: $e');
    }
    return false;
  }

  void _showGasStationDetails(models.GasStation station, {bool isRegistered = false}) {
    String distance = _navigationService.currentLocation != null
        ? station.getDistanceFrom(LatLng(_navigationService.currentLocation!.latitude!, _navigationService.currentLocation!.longitude!))
        : 'Unknown';

    final normalizedPrices = _normalizePricesMap(station.prices ?? {});
    
    // Calculate real-time rating
    final realTimeRating = _calculateAverageRating(_ratings[station.id ?? '']);
    station.rating = realTimeRating;
    station.averageRating = realTimeRating;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            color: Colors.white,
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _markerColorFromBrand(station.brand ?? ''),
                    child: Text((station.brand ?? ' ')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(station.name ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          ),
                          if (isRegistered) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Text(
                                'Registered',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(station.brand ?? '', style: const TextStyle(fontSize: 18)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Flexible(child: _buildInfoCard('Distance', distance, Icons.location_on)),
                  const SizedBox(width: 8),
                  Flexible(child: _buildInfoCard('Rating', realTimeRating.toStringAsFixed(1), Icons.star)),
                  const SizedBox(width: 8),
                  Flexible(child: _buildInfoCard('Status', station.isOpen ? 'Open' : 'Closed', Icons.access_time)),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Gas Prices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...normalizedPrices.entries.map((entry) {
                    final fuelLabel = entry.key[0].toUpperCase() + entry.key.substring(1);
                    final priceVal = entry.value;
                    final reductionAmount = station.getReductionAmount(entry.key);
                    final hasReduction = station.hasPriceReduction(entry.key);
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: InkWell(
                        onTap: () => _onPriceTapShowPerformance(station, fuelLabel),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          child: PriceWithReductionWidget(
                            originalPrice: priceVal,
                            reductionAmount: reductionAmount,
                            fuelType: fuelLabel,
                            onTap: () => _onPriceTapShowPerformance(station, fuelLabel),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 6),
                  Text('Fuel Performance Details:', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ]),
              ),
              const SizedBox(height: 20),
              if (station.amenities.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Current Amenities:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: station.amenities.map((amenity) {
                  final amenityName = amenity is String ? amenity : (amenity['name'] ?? 'Unknown');
                  final hasImages = amenity is Map && amenity['type'] == 'image' && ((amenity['images'] != null && (amenity['images'] as List).isNotEmpty) || amenity['image'] != null);
                  return GestureDetector(
                    onTap: hasImages
                        ? () {
                            final List<String> images = amenity['images'] != null ? List<String>.from(amenity['images']) : (amenity['image'] != null ? [amenity['image']] : []);
                            if (images.isNotEmpty) {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(amenityName),
                                  content: SizedBox(
                                    height: 300,
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
                                  actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
                                ),
                              );
                            }
                          }
                        : null,
                    child: Chip(label: Text(amenityName), avatar: CircleAvatar(backgroundColor: Colors.transparent, child: hasImages ? Row(mainAxisSize: MainAxisSize.min, children: [Icon(_getAmenityIcon(amenityName), color: Colors.blue, size: 18), const SizedBox(width: 2)]) : Icon(_getAmenityIcon(amenityName), color: Colors.blue)), backgroundColor: Colors.blue.shade50),
                  );
                }).toList()),
              ],
              const SizedBox(height: 20),
              if (station.vouchers != null && station.vouchers!.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Available Vouchers:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._buildVoucherWidgets(station),
                const SizedBox(height: 8),
                Text('Tap "Copy Code" to copy the voucher code.', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
              const SizedBox(height: 20),
              Text('Fuel Types: ${station.fuelTypesString}', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                Expanded(child: ElevatedButton.icon(onPressed: () => _startNavigation(station.position), icon: const Icon(Icons.navigation), label: const Text('Navigate'), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)))),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(onPressed: () => _showDirections(station), icon: const Icon(Icons.directions), label: const Text('Directions'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)))),
              ]),
              const SizedBox(height: 20),
              // ---------------- Enhanced Rating + Comment Section ----------------
              Builder(
                builder: (context) {
                  debugPrint('DEBUG: Rendering _CommentRatingSection for station: ${station.name}, id: ${station.id}');
                  debugPrint('DEBUG: Station ratings data: ${_ratings[station.id ?? '']}');
                  debugPrint('DEBUG: Current user ID: ${_getUserId()}');
                  debugPrint('DEBUG: Current user name: ${_getUserName()}');
                  return _CommentRatingSection(
                    station: station,
                    ratings: _ratings,
                    getUserId: _getUserId,
                    getUserName: _getUserName,
                    setRatingForStation: _setRatingForStation,
                    disposed: _disposed,
                    mounted: mounted,
                    updateParentState: () {
                      if (!_disposed && mounted) {
                        setState(() {});
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  models.GasStation? _findStationInList(String stationId) {
    // Look for exact ID match
    var foundStation = _gasStations.firstWhere(
      (s) => s.id == stationId,
      orElse: () => models.GasStation(id: '', name: '', brand: '', prices: {}, position: const LatLng(0, 0)),
    );

    // If not found by ID, try by name (case insensitive)
    if (foundStation.id == null || foundStation.id!.isEmpty) {
      foundStation = _gasStations.firstWhere(
        (s) => s.name?.toLowerCase() == stationId.toLowerCase(),
        orElse: () => models.GasStation(id: '', name: '', brand: '', prices: {}, position: const LatLng(0, 0)),
      );
    }

    // If still not found, try partial name match
    if (foundStation.id == null || foundStation.id!.isEmpty) {
      foundStation = _gasStations.firstWhere(
        (s) => s.name?.toLowerCase().contains(stationId.toLowerCase()) ?? false,
        orElse: () => models.GasStation(id: '', name: '', brand: '', prices: {}, position: const LatLng(0, 0)),
      );
    }

    return foundStation.id != null && foundStation.id!.isNotEmpty ? foundStation : null;
  }

  int _getMarkerColor(String brand) {
    switch (brand.toLowerCase()) {
      case 'shell':
        return Colors.red.value;
      case 'petron':
        return Colors.blue.value;
      case 'caltex':
        return Colors.green.value;
      case 'unioil':
        return Colors.orange.value;
      default:
        return Colors.grey.value;
    }
  }

  String _getPriceForFuelType(models.GasStation station, String fuelType) {
    if (station.prices == null) return 'N/A';

    // Try exact match first
    if (station.prices!.containsKey(fuelType)) {
      final price = station.prices![fuelType];
      return price != null ? price.toStringAsFixed(2) : 'N/A';
    }

    // Try case-insensitive match
    final lowerFuelType = fuelType.toLowerCase();
    for (final key in station.prices!.keys) {
      if (key.toLowerCase() == lowerFuelType) {
        final price = station.prices![key];
        return price != null ? price.toStringAsFixed(2) : 'N/A';
      }
    }

    return 'N/A';
  }

  Future<void> _loadGasStations() async {
    try {
      await services.GasStationService.fetchAndCacheGasStations();
      final stations = services.GasStationService.getAllGasStations();

      // Debug: Log all station IDs and ownerCreated flags
      for (final s in stations) {
        debugPrint('Station loaded: id=${s.id}, ownerCreated=${s.isOwnerCreated}');
      }
      debugPrint('[DEBUG] Checking for specific station FG2025-506562 in loaded stations: ${stations.any((s) => s.id == 'FG2025-506562')}');

      final List<models.GasStation> converted = [];

      for (final s in stations) {
        if (s is models.GasStation) {
          final stationId = s.id ?? s.name ?? '';
          final avg = _calculateAverageRating(_ratings[stationId]);
          converted.add(models.GasStation(
            id: s.id,
            name: s.name,
            brand: s.brand,
            prices: s.prices,
            amenities: s.amenities != null ? List<dynamic>.from(s.amenities!) : [],
            position: s.position,
            isOpen: s.isOpen,
            rating: avg,
            averageRating: avg,
            vouchers: s.vouchers?.map((v) => v.toMap()).toList(),
          ));
        }
      }

      _gasStations = converted;
      _filterAndSearch();

      if (_gasStations.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No gas stations found. Please check your connection.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Error loading stations: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading stations: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterAndSearch() {
    List<models.GasStation> filtered = List<models.GasStation>.from(_gasStations);

    debugPrint('[DEBUG] _filterAndSearch: Starting with ${_gasStations.length} stations');
    debugPrint('[DEBUG] _filterAndSearch: Selected brand: $_selectedBrand, Search query: "$_searchQuery", Sort by: $_sortBy');

    if (_selectedBrand == 'Favorites') {
      filtered = filtered.where((s) => _prefsService.isFavorite(s.id ?? '')).toList();
      debugPrint('[DEBUG] _filterAndSearch: After favorites filter: ${filtered.length} stations');
    } else if (_selectedBrand != 'All') {
      filtered = filtered.where((s) => s.brand == _selectedBrand).toList();
      debugPrint('[DEBUG] _filterAndSearch: After brand filter ($_selectedBrand): ${filtered.length} stations');
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((station) {
        final name = (station.name ?? '').toLowerCase();
        final brand = (station.brand ?? '').toLowerCase();
        final priceMatch = (station.prices?.values ?? []).any((p) => p.toString().contains(q));
        return name.contains(q) || brand.contains(q) || priceMatch;
      }).toList();
      debugPrint('[DEBUG] _filterAndSearch: After search filter ("$q"): ${filtered.length} stations');
    }

    final hasLocation = _navigationService.currentLocation != null;
    final currentLatLng = hasLocation
        ? LatLng(_navigationService.currentLocation!.latitude!, _navigationService.currentLocation!.longitude!)
        : null;

    debugPrint('[DEBUG] _filterAndSearch: Has location: $hasLocation, Current location: $currentLatLng');

    switch (_sortBy) {
      case 'Distance':
        if (hasLocation && currentLatLng != null) {
          filtered.sort((a, b) {
            final da = services.GasStationService.calculateDistance(currentLatLng, a.position ?? const LatLng(0, 0));
            final db = services.GasStationService.calculateDistance(currentLatLng, b.position ?? const LatLng(0, 0));
            return da.compareTo(db);
          });
          debugPrint('[DEBUG] _filterAndSearch: Sorted by distance');
        } else {
          debugPrint('[DEBUG] _filterAndSearch: Cannot sort by distance - no location available');
        }
        break;
      case 'Price':
        filtered.sort((a, b) => (a.priceAsDouble ?? 0).compareTo(b.priceAsDouble ?? 0));
        debugPrint('[DEBUG] _filterAndSearch: Sorted by price');
        break;
      case 'Rating':
        filtered.sort((a, b) {
          final ra = (b.averageRating ?? b.rating ?? 0);
          final rb = (a.averageRating ?? a.rating ?? 0);
          return ra.compareTo(rb);
        });
        debugPrint('[DEBUG] _filterAndSearch: Sorted by rating');
        break;
      default:
        debugPrint('[DEBUG] _filterAndSearch: No sorting applied');
        break;
    }

    debugPrint('[DEBUG] _filterAndSearch: Final filtered stations: ${filtered.length}');
    debugPrint('[DEBUG] _filterAndSearch: Checking if FG2025-506562 is in filtered list: ${filtered.any((s) => s.id == 'FG2025-506562')}');

    if (_disposed || !mounted) return;
    setState(() {
      _filteredGasStations = filtered;
    });
  }

  Future<void> _refreshListData() async {
    try {
      await services.GasStationService.fetchAndCacheGasStations();
      _loadGasStations();
      _filterAndSearch();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('List data refreshed successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Refresh failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh failed: $e'), backgroundColor: Colors.red, duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  double _getMarkerHue(String brand) {
    switch (brand.toLowerCase()) {
      case 'petron':
        return 0;
      case 'shell':
        return 60;
      case 'caltex':
        return 240;
      case 'unioil':
        return 120;
      case 'phoenix':
        return 30;
      default:
        return 270;
    }
  }

  Color _markerColorFromBrand(String brand) {
    final hue = _getMarkerHue(brand);
    return HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
  }

  Map<String, double> _normalizePricesMap(Map<String, dynamic> prices) {
    final Map<String, double> normalized = {};
    prices.forEach((key, value) {
      final normalizedKey = key.toLowerCase();
      final price = (value is num) ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
      if (!normalized.containsKey(normalizedKey) || price < normalized[normalizedKey]!) {
        normalized[normalizedKey] = price;
      }
    });
    return normalized;
  }



  Future<void> _onPriceTapShowPerformance(models.GasStation station, String fuelType) async {
    if (_disposed || !mounted) return;

    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      final stationId = station.id ?? '';
      if (stationId.isEmpty) {
        Navigator.of(context).pop();
        _showSimpleAlert('No station id', 'Station ID not available for fetching performance details.');
        return;
      }

      final stationDoc = await FirestoreService.getGasStation(stationId);
      Navigator.of(context).pop();

      if (stationDoc == null) {
        _showSimpleAlert('Not found', 'Station data not found.');
        return;
      }

      final Map<String, dynamic>? fpAll = (stationDoc['fuelPerformance'] is Map) ? Map<String, dynamic>.from(stationDoc['fuelPerformance']) : null;

      dynamic fpForFuel;
      if (fpAll != null) {
        fpForFuel = fpAll[fuelType] ?? fpAll[fuelType.toLowerCase()] ?? fpAll[fuelType.toUpperCase()];
      }

      if (fpForFuel == null) {
        _showSimpleAlert('No performance data', 'No fuel performance information available for "$fuelType".');
        return;
      }

      String title = '$fuelType Performance';
      List<Widget> rows = [];

      if (fpForFuel is String) {
        rows.add(Text(_cleanDisplayText(fpForFuel), style: const TextStyle(fontSize: 14)));
      } else if (fpForFuel is Map) {
        fpForFuel.forEach((k, v) {
          rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text('${_beautifyKey(k)}:', style: const TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            Expanded(child: Text(_cleanDisplayText(v?.toString() ?? ''))),
          ]));
          rows.add(const SizedBox(height: 8));
        });
      } else {
        rows.add(Text(_cleanDisplayText(fpForFuel.toString())));
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows)),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();
      debugPrint('Error fetching fuel performance: $e');
      _showSimpleAlert('Error', 'Failed to fetch fuel performance: $e');
    }
  }

  // Helper method to build a nicely formatted metrics display
  Widget _buildMetricsDisplay(String metricsText) {
    // Parse the metrics string (remove braces and split by commas)
    String cleanText = metricsText.replaceAll(RegExp(r'[{}]'), '').trim();
    
    if (cleanText.isEmpty) {
      return const Text('No metrics available');
    }
    
    List<String> metrics = cleanText.split(',');
    List<Widget> metricWidgets = [];
    
    for (String metric in metrics) {
      String trimmedMetric = metric.trim();
      if (trimmedMetric.isNotEmpty) {
        // Split by colon to separate key and value
        List<String> parts = trimmedMetric.split(':');
        if (parts.length == 2) {
          String key = _beautifyKey(parts[0].trim());
          String value = parts[1].trim();
          
          metricWidgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Row(
                children: [
                  Text('• ', style: TextStyle(color: Colors.grey[600])),
                  Text('$key: ', style: const TextStyle(fontSize: 13)),
                  Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          );
        }
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: metricWidgets.isEmpty 
          ? [const Text('No metrics available')] 
          : metricWidgets,
    );
  }

  // Helper method to clean up display text and remove unwanted formatting
  String _cleanDisplayText(String text) {
    return text
        .replaceAll(RegExp(r'[{}]'), '') // Remove curly braces
        .replaceAll(RegExp(r'\s+'), ' ') // Replace multiple spaces with single space
        .trim(); // Remove leading/trailing whitespace
  }

  // Improved _beautifyKey method (add this if you don't have it or want to improve it)
  String _beautifyKey(String key) {
    return key
        .replaceAll(RegExp(r'[{}]'), '') // Remove curly braces
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (match) => '${match[1]} ${match[2]}') // Add space before capital letters
        .replaceAll('_', ' ') // Replace underscores with spaces
        .split(' ')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' '); // Capitalize first letter of each word
  }

  Future<Map<String, dynamic>?> _fetchFuelPerformance(String stationId) async {
    debugPrint('Fetching fuel performance for stationId: $stationId');
    try {
      final stationDoc = await FirestoreService.getGasStation(stationId);
      debugPrint('Station doc fetched: $stationDoc');
      if (stationDoc == null) {
        debugPrint('Station doc is null');
        return null;
      }
      final fuelPerf = stationDoc['fuelPerformance'];
      debugPrint('Fuel performance raw: $fuelPerf');
      if (fuelPerf is Map) {
        final result = Map<String, dynamic>.from(fuelPerf);
        debugPrint('Fuel performance processed: $result');
        return result;
      } else {
        debugPrint('Fuel performance is not a Map: ${fuelPerf.runtimeType}');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching fuel performance: $e');
      return null;
    }
  }


  void _showSimpleAlert(String title, String message) {
    if (_disposed || !mounted) return;
    showDialog(context: context, builder: (context) => AlertDialog(title: Text(title), content: Text(message), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))]));
  }

  Widget _buildInteractiveRatingStars({
    required double rating,
    required String stationKey,
    required String username,
    required ValueChanged<double> onSelected,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        return IconButton(
          icon: Icon(rating >= starIndex ? Icons.star : Icons.star_border, color: Colors.amber),
          onPressed: () {
            onSelected(starIndex.toDouble());
          },
        );
      }),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
      child: Column(children: [Icon(icon, color: Colors.blue), const SizedBox(height: 4), Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)), Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))]),
    );
  }

  void _startNavigation(LatLng destination) async {
    await _navigationService.startNavigation(destination);
    if (_disposed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Navigation started! Switch to Maps tab to see the route.'),
        action: SnackBarAction(label: 'Go to Maps', onPressed: () {}),
      ),
    );
  }

  void _showDirections(models.GasStation station) {
    String distance = _navigationService.currentLocation != null
        ? station.getDistanceFrom(LatLng(_navigationService.currentLocation!.latitude!, _navigationService.currentLocation!.longitude!))
        : 'Unknown';
    if (_disposed || !mounted) return;
    final double? price = station.prices?[_selectedFuelType];
    final priceText = price != null ? '₱${price.toStringAsFixed(2)}' : 'N/A';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Directions to ${station.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('📍 ${station.name}'),
          Text('⛽ ${station.brand}'),
          Text('💰 $priceText'),
          Text('📏 Distance: $distance'),
          Text('⭐ ${station.formattedRating}'),
          const SizedBox(height: 10),
          const Text('Tap "Navigate" to start real-time navigation with turn-by-turn directions.', style: TextStyle(fontStyle: FontStyle.italic)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(onPressed: () {
            Navigator.pop(context);
            _startNavigation(station.position);
          }, child: const Text('Navigate')),
        ],
      ),
    );
  }

  void _showAmenityImage(BuildContext context, String imageUrl, String amenityName, String description) {
    showDialog(context: context, barrierDismissible: true, builder: (BuildContext context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
              child: Row(children: [
                Expanded(child: Text(amenityName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            if (imageUrl.isNotEmpty)
  SizedBox(
    height: 250,
    child: InteractiveViewer(
      panEnabled: true,
      boundaryMargin: const EdgeInsets.all(20),
      minScale: 0.5,
      maxScale: 4.0,
      child: Image.network(imageUrl, fit: BoxFit.contain),
    ),
  )
else
  Container(height: 200, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12))), child: const Icon(Icons.image_not_supported, size: 50, color: Colors.grey)),
            if (description.isNotEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text(description, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center)),
          ]),
        ),
      );
    });
  }

  Widget _brokenImagePlaceholder() {
    return Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, size: 50, color: Colors.grey));
  }

  Future<void> _requestPermissionAndFetchLocation() async {
    final permission = await _locationService.requestPermission();
    if (permission == PermissionStatus.granted) {
      final location = await _locationService.getLocation();
      _navigationService.updateLocation(location);

      _locationService.onLocationChanged.listen((loc) {
        _navigationService.updateLocation(loc);
      });
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if we're being used as a tab in HomeScreen (no route arguments = tab mode)
    final isTabMode = ModalRoute.of(context)?.settings.arguments == null;

    {
      // Full screen mode: Use Scaffold for standalone navigation
      return Scaffold(
        appBar: AppBar(
  title: const Text(
    'Gas Stations',
    style: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 20,
    ),
  ),
  elevation: 2,
  // or use `surfaceTintColor` for Material 3
),
        body: RefreshIndicator(
          onRefresh: _refreshListData,
          child: Column(children: [
            _buildSearchBar(),
            _buildFilterSortBar(),
            Expanded(
              child: _filteredGasStations.isEmpty ? const Center(child: Text('No gas stations found')) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _filteredGasStations.length, itemBuilder: (context, index) {
                final station = _filteredGasStations[index];
                return _buildGasStationTile(station);
              }),
            ),
          ]),
        ),
      );
    }
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search gas stations, brands, or prices...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(icon: Icon(_showFilters ? Icons.filter_list : Icons.filter_list_outlined), onPressed: () {
            setState(() {
              _showFilters = !_showFilters;
            });
          }),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey[100],
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
          _filterAndSearch();
        },
      ),
    );
  }

  Widget _buildFilterSortBar() {
    // Helper method to convert string to title case
    String _toTitleCase(String text) {
      if (text.isEmpty) return text;
      return text.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }

    // Normalize fuel types to title case to avoid duplicates like "regular" and "Regular"
    final allFuelTypes = _gasStations
        .expand((s) => (s.prices?.keys ?? const <String>[]) as Iterable<String>)
        .map((type) => _toTitleCase(type))
        .toSet()
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
        Container(
          width: 150,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[300]!)),
          child: DropdownButton<String>(
            value: _selectedFuelType,
            isExpanded: true,
            onChanged: (String? newValue) {
              if (newValue != null) {
                _prefsService.setPreferredFuelType(newValue);
                _filterAndSearch();
              }
            },
            items: allFuelTypes.map((value) => DropdownMenuItem<String>(value: value, child: Text(value, overflow: TextOverflow.ellipsis))).toList(),
            underline: Container(),
            isDense: true,
          ),
        ),
          const SizedBox(width: 8),
          ElevatedButton.icon(onPressed: () => _showSortOptions(), icon: const Icon(Icons.sort), label: Text(_sortBy), style: ElevatedButton.styleFrom(elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)))),
          const SizedBox(width: 8),
          ElevatedButton.icon(onPressed: () => _showFilterOptions(), icon: const Icon(Icons.filter_list), label: const Text('Filter'), style: ElevatedButton.styleFrom(elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)))),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _selectedFuelType = 'Regular';
                _selectedBrand = 'All';
                _sortBy = 'Distance';
                _searchQuery = '';
              });
              _prefsService.setPreferredFuelType('Regular');
              _filterAndSearch();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reset'),
            style: ElevatedButton.styleFrom(elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), backgroundColor: Colors.grey[200], foregroundColor: Colors.black),
          ),
        ]),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(context: context, builder: (context) => Container(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Sort by', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(spacing: 8.0, children: ['Distance', 'Price', 'Rating'].map((sort) {
          return ChoiceChip(label: Text(sort), selected: _sortBy == sort, onSelected: (selected) {
            if (selected) {
              setState(() {
                _sortBy = sort;
                _filterAndSearch();
              });
              Navigator.pop(context);
            }
          });
        }).toList()),
      ]),
    ));
  }

  void _showFilterOptions() {
    final brands = ['All', 'Favorites'] + services.GasStationService.getUniqueBrands();
    showModalBottomSheet(context: context, builder: (context) => Container(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Filter by Brand', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(spacing: 8.0, children: brands.map((brand) {
          return ChoiceChip(label: Text(brand), selected: _selectedBrand == brand, onSelected: (selected) {
            if (selected) {
              setState(() {
                _selectedBrand = brand;
                _filterAndSearch();
              });
              Navigator.pop(context);
            }
          });
        }).toList()),
      ]),
    ));
  }

  Widget _buildGasStationTile(models.GasStation station) {
    String distance = _navigationService.currentLocation != null
        ? station.getDistanceFrom(LatLng(_navigationService.currentLocation!.latitude!, _navigationService.currentLocation!.longitude!))
        : 'Calculating...';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showGasStationDetails(station),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Color(_getMarkerColor(station.brand ?? '').toInt()).withOpacity(0.2),
                child: Text((station.brand ?? ' ')[0].toUpperCase(), style: TextStyle(color: Color(_getMarkerColor(station.brand ?? '').toInt()), fontWeight: FontWeight.bold, fontSize: 20)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(station.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${station.brand ?? ''} - $distance away', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _buildRatingStars(station.averageRating ?? station.rating ?? 0),
                const SizedBox(height: 4),
                Text(station.isOpen ? 'Open' : 'Closed', style: TextStyle(color: station.isOpen ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
              ]),
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                IconButton(
                  icon: Icon(
                    _prefsService.isFavorite(station.id ?? '') ? Icons.favorite : Icons.favorite_border,
                    color: _prefsService.isFavorite(station.id ?? '') ? Colors.red : Colors.grey,
                    size: 24,
                  ),
                  onPressed: () {
                    _prefsService.toggleFavoriteStation(station.id ?? '');
                    setState(() {});
                  },
                  tooltip: _prefsService.isFavorite(station.id ?? '') ? 'Remove from favorites' : 'Add to favorites',
                ),
                const SizedBox(width: 8),
                if (_navigationService.isNavigating && station.position == _navigationService.destination)
                  const Text('Navigating...', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))
                else
                  ElevatedButton.icon(onPressed: () => _startNavigation(station.position), icon: const Icon(Icons.navigation, size: 18), label: const Text('Navigate'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)))),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₱${_getPriceForFuelType(station, _selectedFuelType)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                const Text('/L', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildRatingStars(double rating) {
    final fullCount = rating.floor();
    return Row(children: List.generate(5, (index) => Icon(index < fullCount ? Icons.star : Icons.star_border, color: Colors.amber, size: 16)));
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

  String _getUserName() {
    final user = AuthService().currentUser;
    if (user == null) return 'You';

    // Instead of using displayName (which is role like 'customer'), fetch actual user name from Firestore
    String userName = 'You';

    // Async fetch user name from Firestore synchronously is not possible here,
    // so we use a cached map or fallback to email prefix or uid.
    // For now, fallback to email prefix or uid.
    if (user.email != null && user.email!.isNotEmpty) {
      userName = user.email!.split('@').first;
    } else if (user.uid.isNotEmpty) {
      userName = user.uid;
    }

    debugPrint('User displayName: ${user.displayName}');
    debugPrint('User email: ${user.email}');
    debugPrint('Using userName: $userName');

    return userName;
  }

  String _getUserId() {
    final user = AuthService().currentUser;
    return user?.uid ?? 'anonymous';
  }

  double _calculateAverageRating(Map<String, Map<String, dynamic>>? ratings) {
    if (ratings == null || ratings.isEmpty) return 0.0;
    double sum = 0.0;
    int count = 0;
    ratings.forEach((uid, data) {
      final r = data['rating'];
      if (r is num) {
        sum += r.toDouble();
        count++;
      }
    });
    return count == 0 ? 0.0 : sum / count;
  }

  // ----------------- Ratings persistence & helpers -----------------

  Future<void> _loadRatingsFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('station_ratings');
      if (jsonString == null || jsonString.isEmpty) {
        _ratings = {};
        return;
      }
      final Map<String, dynamic> decoded = json.decode(jsonString);
      final Map<String, Map<String, Map<String, dynamic>>> rebuilt = {};
      decoded.forEach((stationId, userMap) {
        if (userMap is Map<String, dynamic>) {
          final Map<String, Map<String, dynamic>> inner = {};
          userMap.forEach((uid, entry) {
            if (entry is Map<String, dynamic>) {
              inner[uid] = {
                'name': entry['name'] ?? uid,
                'rating': (entry['rating'] is num) ? (entry['rating'] as num).toDouble() : 0.0,
                'comment': entry['comment'] ?? '',
                'updatedAt': (entry['updatedAt'] is num) ? (entry['updatedAt'] as num).toInt() : 0,
              };
            }
          });
          rebuilt[stationId] = inner;
        }
      });

      // Fix placeholder names via UserServiceFixed
      for (var stationEntry in rebuilt.entries) {
        final stationId = stationEntry.key;
        final userMap = stationEntry.value;
        final userIdsToFix = <String>[];
        userMap.forEach((uid, data) {
          final name = data['name']?.toString().toLowerCase() ?? '';
          if (name == 'user' || name == 'unknown user') {
            userIdsToFix.add(uid);
          }
        });
        if (userIdsToFix.isNotEmpty) {
          final userNames = await UserServiceFixed.getUserNames(userIdsToFix);
          for (var uid in userIdsToFix) {
            userMap[uid]?['name'] = userNames[uid] ?? uid;
          }
        }
      }

      if (_disposed || !mounted) {
        _ratings = rebuilt;
      } else {
        setState(() {
          _ratings = rebuilt;
        });
      }
    } catch (e) {
      debugPrint('Failed to load ratings: $e');
    }
  }

  Future<void> _saveRatingsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('station_ratings', json.encode(_ratings));
    } catch (e) {
      debugPrint('Failed to save ratings: $e');
    }
  }

  Future<void> _setRatingForStation(String stationKey, String uid, String displayName, double rating, {String? comment}) async {
    if (stationKey.isEmpty) return;

    // Override displayName with actual user name fetched from Firestore to avoid 'customer' role name
    String actualUserName = displayName;
    try {
      final fetchedName = await AuthService().getUserName(uid);
      if (fetchedName != null && fetchedName.isNotEmpty) {
        actualUserName = fetchedName;
      }
    } catch (e) {
      debugPrint('Error fetching actual user name: $e');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Save to local storage
    _ratings[stationKey] ??= {};
    _ratings[stationKey]![uid] = {
      'name': actualUserName,
      'rating': rating,
      'comment': comment ?? '',
      'updatedAt': now,
    };
    await _saveRatingsToStorage();

    // Also save to Firestore
    try {
      await FirestoreService.setRatingWithCommentInStationRatings(
        stationId: stationKey,
        userId: uid,
        userName: actualUserName,
        rating: rating,
        comment: comment,
      );
    } catch (e) {
      debugPrint('Error saving rating to Firestore: $e');
    }
  }

  // Persist changes locally when the modal closes (keeps local cache in sync)
  Future<void> _maybeSaveCommentOnClose(String stationKeyLocal, String uidLocal, String displayNameLocal, double ratingLocal, String commentText) async {
    final existing = (_ratings[stationKeyLocal]?[uidLocal]?['comment'] as String?) ?? '';
    final newText = commentText.trim();

    if (existing != newText) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _ratings[stationKeyLocal] ??= {};
      _ratings[stationKeyLocal]![uidLocal] = {
        'name': displayNameLocal,
        'rating': ratingLocal,
        'comment': newText,
        'updatedAt': now,
      };
      await _setRatingForStation(stationKeyLocal, uidLocal, displayNameLocal, ratingLocal, comment: newText);

      if (!_disposed && mounted) {
        setState(() {});
      }
    }
  }

  void _setupRealtimePriceListener() {
    _realtimePriceSubscription = FirebaseFirestore.instance.collection('gas_stations').snapshots().listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        services.GasStationService.clearCache();
        _loadGasStations();
      }
    });
  }

  /// Listen to station_ratings collection and update local _ratings map so
  /// UI (tiles + averages) always reflect Firestore in near real-time.
  void _setupRatingsRealtimeListener() {
    _ratingsSubscription = FirebaseFirestore.instance.collection('station_ratings').snapshots().listen((snapshot) {
      // Build map: stationId => { userId: { name, rating, comment, updatedAt } }
      final Map<String, Map<String, Map<String, dynamic>>> rebuilt = {};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final stationId = (data['stationId'] ?? '') as String;
        final userId = (data['userId'] ?? '') as String;
        if (stationId.isEmpty || userId.isEmpty) continue;

        rebuilt[stationId] ??= {};
        rebuilt[stationId]![userId] = {
          'name': data['userName'] ?? userId,
          'rating': (data['rating'] is num) ? (data['rating'] as num).toDouble() : 0.0,
          'comment': data['comment'] ?? '',
          'updatedAt': (data['updatedAt'] is num) ? (data['updatedAt'] as num).toInt() : 0,
        };
      }

      // Merge with local ratings, preferring newer timestamps
      final Map<String, Map<String, Map<String, dynamic>>> merged = {};
      rebuilt.forEach((stationId, userMap) {
        merged[stationId] ??= {};
        userMap.forEach((userId, firestoreEntry) {
          final localEntry = _ratings[stationId]?[userId];
          if (localEntry != null) {
            final localUpdatedAt = (localEntry['updatedAt'] as num?)?.toInt() ?? 0;
            final firestoreUpdatedAt = (firestoreEntry['updatedAt'] as num?)?.toInt() ?? 0;
            if (localUpdatedAt > firestoreUpdatedAt) {
              // Keep local version if newer
              merged[stationId]![userId] = localEntry;
            } else {
              // Use Firestore version
              merged[stationId]![userId] = firestoreEntry;
            }
          } else {
            // No local version, use Firestore
            merged[stationId]![userId] = firestoreEntry;
          }
        });
      });

      // Also include any local ratings not in Firestore
      _ratings.forEach((stationId, userMap) {
        merged[stationId] ??= {};
        userMap.forEach((userId, localEntry) {
          if (!merged[stationId]!.containsKey(userId)) {
            merged[stationId]![userId] = localEntry;
          }
        });
      });

      // Update local cache & storage
      _ratings = merged;
      _saveRatingsToStorage();

      // Recompute UI station ratings by reloading gas stations (simple and safe)
      _loadGasStations();
    }, onError: (err) {
      debugPrint('Ratings listener error: $err');
    });
  }

  List<Widget> _buildVoucherWidgets(models.GasStation station) {
    if (station.vouchers == null || station.vouchers!.isEmpty) {
      return [];
    }

    final List<Widget> voucherWidgets = [];

    for (final voucherData in station.vouchers!) {
      try {
        final voucher = Voucher.fromMap(voucherData as Map<String, dynamic>);

        voucherWidgets.add(
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: voucher.isValid ? Colors.green.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: voucher.isValid ? Colors.green.shade200 : Colors.grey.shade300,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        voucher.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!voucher.isValid)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Expired',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  voucher.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Code: ${voucher.code}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Valid until: ${voucher.validUntil.toString().split(' ')[0]}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (voucher.isValid)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: voucher.code));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Voucher code "${voucher.code}" copied to clipboard!'),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy Code'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      } catch (e) {
        debugPrint('Error parsing voucher: $e');
        // Skip invalid voucher data
        continue;
      }
    }

    return voucherWidgets;
  }
}

// ----------------- Comment & Rating Widget (overlapping thank-you banner) -----------------
class _CommentRatingSection extends StatefulWidget {
  final models.GasStation station;
  final Map<String, Map<String, Map<String, dynamic>>> ratings;
  final String Function() getUserId;
  final String Function() getUserName;
  final Future<void> Function(String stationKey, String uid, String displayName, double rating, {String? comment}) setRatingForStation;
  final bool disposed;
  final bool mounted;
  final VoidCallback updateParentState;

  const _CommentRatingSection({
    Key? key,
    required this.station,
    required this.ratings,
    required this.getUserId,
    required this.getUserName,
    required this.setRatingForStation,
    required this.disposed,
    required this.mounted,
    required this.updateParentState,
  }) : super(key: key);

  @override
  State<_CommentRatingSection> createState() => _CommentRatingSectionState();
}

class _CommentRatingSectionState extends State<_CommentRatingSection> {
  late final String _stationKey;
  late final String _uid;
  late final String _userName;
  double _currentRating = 0.0;
  final TextEditingController _commentController = TextEditingController();
  bool _saving = false;

  /// Controls editor visibility. If user already has saved review, editor is hidden initially.
  bool _editorVisible = true;

  /// Controls showing the overlapping thank-you banner
  bool _showThankYou = false;

  /// Duration the thank-you banner will remain visible
  final Duration thankYouDuration = const Duration(seconds: 3);

  Timer? _thankYouTimer;

  @override
  void initState() {
    super.initState();
    _stationKey = widget.station.id ?? widget.station.name ?? '';
    _uid = widget.getUserId();
    _userName = widget.getUserName();

    final stationRatings = widget.ratings[_stationKey];
    if (stationRatings != null && stationRatings.containsKey(_uid)) {
      final userEntry = stationRatings[_uid]!;
      _currentRating = (userEntry['rating'] is num) ? (userEntry['rating'] as num).toDouble() : 0.0;
      _commentController.text = (userEntry['comment'] as String?) ?? '';
      // Hide editor initially if the user already has a saved review (rating > 0 or non-empty comment)
      _editorVisible = !((_currentRating > 0.0) || (_commentController.text.trim().isNotEmpty));
    } else {
      _currentRating = 0.0;
      _editorVisible = true;
    }
  }

  @override
  void dispose() {
    _thankYouTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _saveRatingAndComment() async {
    if (_stationKey.isEmpty) return;
    if (_saving) return;

    setState(() => _saving = true);
    try {
      final commentText = _commentController.text.trim();
      await widget.setRatingForStation(_stationKey, _uid, _userName, _currentRating, comment: commentText);

      // Ask parent to refresh and reflect changes in the outer UI
      widget.updateParentState();

      // Hide the editor after successful save (as requested)
      if (mounted) setState(() => _editorVisible = false);

      // Show the overlapping thank-you banner (instead of popup)
      if (mounted) {
        setState(() => _showThankYou = true);
        // auto-hide after duration
        _thankYouTimer?.cancel();
        _thankYouTimer = Timer(thankYouDuration, () {
          if (mounted) setState(() => _showThankYou = false);
        });
      }
    } catch (e) {
      debugPrint('Error submitting rating: $e');
      if (widget.mounted && !widget.disposed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save rating: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteRating() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete review'),
        content: const Text('Are you sure you want to delete your rating and comment?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Using the same callback: set rating to 0.0 and comment to '' — adapt if you prefer a dedicated delete method.
      await widget.setRatingForStation(_stationKey, _uid, _userName, 0.0, comment: '');

      // Remove locally and update parent to re-render lists
      widget.ratings[_stationKey]?.remove(_uid);
      widget.updateParentState();

      if (widget.mounted && !widget.disposed) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your review was deleted'), duration: Duration(seconds: 2)));
      }

      // Reset local editor and show it so user can submit anew
      if (mounted) {
        setState(() {
          _currentRating = 0.0;
          _commentController.clear();
          _editorVisible = true;
        });
      }
    } catch (e) {
      debugPrint('Error deleting rating: $e');
      if (widget.mounted && !widget.disposed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete review: $e')));
      }
    }
  }

  Widget _interactiveStars({double? initial}) {
    final value = initial ?? _currentRating;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        final filled = value >= starIndex;
        return IconButton(
          icon: Icon(filled ? Icons.star : Icons.star_border, color: Colors.amber),
          iconSize: 28,
          onPressed: () {
            setState(() {
              _currentRating = starIndex.toDouble();
            });
          },
        );
      }),
    );
  }

  void _showCommentOptions(String ownerUid, Map<String, dynamic> entry) {
    // Only allow options for the current user's comment
    if (ownerUid != _uid) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit your review'),
            onTap: () {
              Navigator.of(context).pop();
              // Populate editor with existing values and show it
              setState(() {
                _currentRating = (entry['rating'] is num) ? (entry['rating'] as num).toDouble() : 0.0;
                _commentController.text = (entry['comment'] as String?) ?? '';
                _editorVisible = true; // re-open editor for editing
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('Delete your review'),
            onTap: () {
              Navigator.of(context).pop();
              _deleteRating();
            },
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Cancel'),
            onTap: () => Navigator.of(context).pop(),
          ),
        ]),
      ),
    );
  }

  // Helper to build initials from name
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  List<Widget> _buildCommentsList() {
    final List<Widget> rows = [];
    final stationRatings = widget.ratings[_stationKey];
    if (stationRatings == null || stationRatings.isEmpty) {
      rows.add(const Padding(padding: EdgeInsets.only(top: 8), child: Text('No ratings or comments yet. Be the first!')));
      return rows;
    }

    // Sort entries (desc by rating then name)
    final entries = stationRatings.entries.toList()
      ..sort((a, b) {
        final ra = (a.value['rating'] is num) ? (a.value['rating'] as num).toDouble() : 0.0;
        final rb = (b.value['rating'] is num) ? (b.value['rating'] as num).toDouble() : 0.0;
        if (rb.compareTo(ra) != 0) return rb.compareTo(ra);
        return (a.value['name'] ?? a.key).toString().compareTo((b.value['name'] ?? b.key).toString());
      });

    for (final e in entries) {
      final ownerUid = e.key;
      final name = (e.value['name'] ?? e.key).toString();
      final rating = (e.value['rating'] is num) ? (e.value['rating'] as num).toDouble() : 0.0;
      final comment = (e.value['comment'] as String?) ?? '';

      final initials = _initials(name);
      final isMine = ownerUid == _uid;

      // Visual decoration for own comment
      final tileContent = ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: isMine ? Colors.green.shade400 : Colors.grey.shade400,
          child: Text(
            isMine ? 'You' : initials,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              // Badge indicating whether it's you or other user
              Chip(
                label: Text(isMine ? 'You' : 'User', style: TextStyle(fontSize: 12, color: isMine ? Colors.green.shade800 : Colors.grey.shade700)),
                backgroundColor: isMine ? Colors.green.shade50 : Colors.grey.shade200,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Row(children: List.generate(5, (i) => Icon(i < rating.round() ? Icons.star : Icons.star_border, size: 14, color: Colors.amber))),
        ]),
        subtitle: comment.isNotEmpty ? Padding(padding: const EdgeInsets.only(top: 6), child: Text(comment)) : null,
      );

      Widget tileWrapper;
      if (isMine) {
        // Make own comment visually distinct and long-pressable
        tileWrapper = InkWell(
          onLongPress: () => _showCommentOptions(ownerUid, e.value),
          child: Container(
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.all(8),
            child: Column(children: [tileContent, const Divider(height: 8)]),
          ),
        );
      } else {
        tileWrapper = Column(children: [tileContent, const Divider(height: 8)]);
      }

      rows.add(tileWrapper);
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    // Calculate real-time average rating from the ratings data
    final stationRatings = widget.ratings[widget.station.id ?? ''];
final avg = stationRatings != null && stationRatings.isNotEmpty
    ? stationRatings.values
        .map((data) => (data['rating'] as num?)?.toDouble() ?? 0.0)
        .where((rating) => rating > 0)
        .fold(0.0, (sum, rating) => sum + rating) / 
        stationRatings.values
            .map((data) => (data['rating'] as num?)?.toDouble() ?? 0.0)
            .where((rating) => rating > 0)
            .length
    : widget.station.averageRating ?? widget.station.rating ?? 0.0;

    // Build the editor area (only when visible)
    final editorArea = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Your rating:', style: TextStyle(fontWeight: FontWeight.w600)),
      _interactiveStars(),
      const SizedBox(height: 8),
      TextField(
        controller: _commentController,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: 'Write a comment (optional)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        ElevatedButton.icon(
          onPressed: _saving ? null : _saveRatingAndComment,
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
          label: Text(_saving ? 'Saving...' : 'Save'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () {
            final stationRatings = widget.ratings[_stationKey];
            if (stationRatings != null && stationRatings.containsKey(_uid)) {
              final userEntry = stationRatings[_uid]!;
              setState(() {
                _currentRating = (userEntry['rating'] is num) ? (userEntry['rating'] as num).toDouble() : 0.0;
                _commentController.text = (userEntry['comment'] as String?) ?? '';
              });
            } else {
              setState(() {
                _currentRating = 0.0;
                _commentController.clear();
              });
            }
          },
          child: const Text('Reset'),
        ),
      ]),
      const SizedBox(height: 12),
      const Divider(),
    ]);

    // Reviews list widget
    final reviewsList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text('All reviews', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._buildCommentsList(),
      ],
    );

    // Overlapping thank-you banner - appears centered over the reviews area
    final thankYouBanner = AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _showThankYou ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !_showThankYou,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white..withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0, 6)),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.thumb_up, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text('Thank you for Rating and Commenting. Your feedback is deeply appreciated!', style: const TextStyle(fontSize: 14))),
            ]),
          ),
        ),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Ratings & Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Text(avg.toStringAsFixed(1), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Row(children: List.generate(5, (i) => Icon(i < avg.round() ? Icons.star : Icons.star_border, size: 18, color: Colors.amber))),
        ]),
        Text('${stationRatings?.length ?? 0} reviews', style: const TextStyle(color: Colors.grey)),
      ]),
      const SizedBox(height: 12),

      // Editor (if visible)
      if (_editorVisible) editorArea,

      // The reviews + overlapping banner are stacked so the banner overlaps when visible
      Stack(
        alignment: Alignment.center,
        children: [
          reviewsList,
          // Show banner only when editor is hidden and _showThankYou is true
          if (!_editorVisible && _showThankYou) Positioned.fill(child: Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 12), child: thankYouBanner))),
        ],
      ),
    ]);
  }
}
