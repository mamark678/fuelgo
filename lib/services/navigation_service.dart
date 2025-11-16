import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

import 'location_tracking_service.dart';
import 'voice_navigation_service.dart';

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  // Navigation state
  bool _isNavigating = false;
  LatLng? _destination;
  List<Polyline> _polylines = [];
  PolylinePoints _polylinePoints = PolylinePoints();
  LocationData? _currentLocation;
  
  // Enhanced navigation data
  List<RouteStep> _routeSteps = [];
  String _eta = '';
  String _distance = '';
  String _duration = '';
  String _nextTurn = '';
  int _currentStepIndex = 0;
  double? _currentSpeed;
  List<Map<String, dynamic>> _alternativeRoutes = [];

  // Real-time updates with separate turn checking
  DateTime? _lastApiCall;
  static const Duration _apiCooldown = Duration(seconds: 30);
  Timer? _turnCheckTimer;
  static const Duration _turnCheckInterval = Duration(seconds: 3);

  // Voice navigation service
  final VoiceNavigationService _voiceService = VoiceNavigationService();

  // Location tracking service for real-time updates
  final LocationTrackingService _locationTrackingService = LocationTrackingService();

  // Listeners for UI updates
  final List<Function()> _listeners = [];

  // HTTP client with timeout
  static final http.Client _httpClient = http.Client();

  // Getters
  bool get isNavigating => _isNavigating;
  LatLng? get destination => _destination;
  List<Polyline> get polylines => _polylines;
  LocationData? get currentLocation => _currentLocation;
  List<RouteStep> get routeSteps => _routeSteps;
  String get eta => _eta;
  String get distance => _distance;
  String get duration => _duration;
  String get nextTurn => _nextTurn;
  int get currentStepIndex => _currentStepIndex;
  double? get currentSpeed => _currentSpeed;
  List<Map<String, dynamic>> get alternativeRoutes => _alternativeRoutes;
  LatLng? get currentDestination => _destination;

  // Initialize voice navigation
  Future<void> initializeVoiceNavigation() async {
    await _voiceService.initialize();
  }

  // Set voice enabled/disabled
  void setVoiceEnabled(bool enabled) {
    _voiceService.setEnabled(enabled);
  }

  // Add listener for UI updates
  void addListener(Function() listener) {
    _listeners.add(listener);
  }

  // Remove listener
  void removeListener(Function() listener) {
    _listeners.remove(listener);
  }

  // Optimized listener notification
  void _notifyListeners() {
    scheduleMicrotask(() {
      final listenersCopy = List<Function()>.from(_listeners);
      for (var listener in listenersCopy) {
        try {
          listener();
        } catch (e) {
          print('Removing faulty listener due to error: $e');
          _listeners.remove(listener);
        }
      }
    });
  }

  // Dispose method with proper cleanup
  void dispose() {
    _listeners.clear();
    _turnCheckTimer?.cancel();
    stopNavigation();
  }

  // Real-time location updates without debouncing
  void updateLocation(LocationData location) {
    _currentLocation = location;
    _currentSpeed = location.speed;
    
    if (_isNavigating && _destination != null) {
      // Immediately update UI for real-time tracking
      _notifyListeners();
      
      // Recalculate ETA based on current speed (non-blocking)
      _recalculateETAWithSpeed();
    } else {
      _notifyListeners();
    }
  }

  // Improved navigation start with better error handling
  Future<void> startNavigation(LatLng destination) async {
    if (destination.latitude == 0.0 && destination.longitude == 0.0 ||
        destination.latitude.isNaN || destination.longitude.isNaN) {
      print('❌ Invalid destination coordinates: $destination');
      _isNavigating = false;
      _destination = null;
      _polylines.clear();
      _distance = 'Error';
      _duration = 'Error';
      _eta = 'Error';
      _nextTurn = 'Invalid destination location';
      _notifyListeners();
      return;
    }

    try {
      print('🚀 Starting navigation to: ${destination.latitude}, ${destination.longitude}');
      
      // Reset all navigation state
      _turnCheckTimer?.cancel();
      _isNavigating = false;
      _destination = null;
      _polylines.clear();
      _routeSteps.clear();
      _alternativeRoutes.clear();
      _distance = '';
      _duration = '';
      _eta = '';
      _nextTurn = '';
      _currentStepIndex = 0;
      _lastApiCall = null;

      _destination = destination;
      _isNavigating = true;
      _currentStepIndex = 0;

      _distance = 'Loading...';
      _duration = 'Loading...';
      _eta = 'Loading...';
      _nextTurn = 'Calculating route...';
      _notifyListeners();

      // Get current location
      print('📍 Refreshing current location for navigation...');
      final Location location = Location();
      try {
        _currentLocation = await location.getLocation().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('Location timeout'),
        );
        print('✅ Current location obtained: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
      } catch (e) {
        print('❌ Failed to get current location: $e');
        _isNavigating = false;
        _destination = null;
        _polylines.clear();
        _distance = 'Error';
        _duration = 'Error';
        _eta = 'Error';
        _nextTurn = 'Unable to get current location';
        _notifyListeners();
        return;
      }
      
      // Get route
      await _getRouteToDestination();
      
      // Start periodic turn checking (separate from location updates)
      _startTurnChecking();

      // Start real-time location tracking for navigation updates
      await _locationTrackingService.enableNavigationMode();
      await _locationTrackingService.startTracking(onUpdate: updateLocation);

      // Voice announcement
      _voiceService.speakRouteStart('your destination');
      
      print('✅ Navigation started successfully');
    } catch (e) {
      print('❌ Error starting navigation: $e');
      _isNavigating = false;
      _destination = null;
      _polylines.clear();
      _distance = 'Error';
      _duration = 'Error';
      _eta = 'Error';
      _nextTurn = 'Navigation failed';
      _notifyListeners();
      return;
    }
  }

  // Start periodic turn checking (separate from location updates)
  void _startTurnChecking() {
    _turnCheckTimer?.cancel();
    _turnCheckTimer = Timer.periodic(_turnCheckInterval, (timer) {
      if (_isNavigating) {
        _checkNextTurn();
      } else {
        timer.cancel();
      }
    });
  }

  // Stop navigation
  void stopNavigation() {
    _turnCheckTimer?.cancel();
    _locationTrackingService.stopTracking();
    _isNavigating = false;
    _destination = null;
    _polylines.clear();
    _routeSteps.clear();
    _eta = '';
    _distance = '';
    _duration = '';
    _nextTurn = '';
    _currentStepIndex = 0;
    _lastApiCall = null;

    _voiceService.speakRouteEnd();

    _notifyListeners();
  }

  // Route fetching with API cooldown
  Future<void> _getRouteToDestination() async {
    if (_currentLocation == null || _destination == null) {
      print('❌ Cannot get route: missing location data');
      _setErrorValues();
      return;
    }

    if (_lastApiCall != null &&
        DateTime.now().difference(_lastApiCall!) < _apiCooldown) {
      print('⏰ API cooldown active, skipping request');
      return;
    }

    try {
      print('🌐 Fetching route from OSRM API...');
      _lastApiCall = DateTime.now();

      final String url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${_currentLocation!.longitude is int ? (_currentLocation!.longitude as int).toDouble() : _currentLocation!.longitude},'
          '${_currentLocation!.latitude is int ? (_currentLocation!.latitude as int).toDouble() : _currentLocation!.latitude};'
          '${_destination!.longitude},${_destination!.latitude}?overview=full&geometries=geojson&steps=true&alternatives=true';

      final response = await _httpClient.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Flutter/NavigationApp',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('API request timeout'),
      );

      print('📡 OSRM API response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('📊 API Response Code: ${data['code']}');

        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          await _processRouteDataOSRM(data);
          await _createPolylineOSRM(data);
        } else {
          final errorMsg = data['message'] ?? data['code'] ?? 'Unknown error';
          print('❌ OSRM API error: $errorMsg');
          throw Exception('API Error: $errorMsg');
        }
      } else {
        print('❌ HTTP error: ${response.statusCode}');
        throw Exception('HTTP Error: ${response.statusCode}');
      }

    } catch (e) {
      print('❌ Error getting route: $e');
      _setErrorValues();
      rethrow;
    }
  }

  // OSRM route data processing
  Future<void> _processRouteDataOSRM(Map<String, dynamic> data) async {
    try {
      final route = data['routes'][0];
      final legs = route['legs'];

      if (legs.isNotEmpty) {
        final leg = legs[0];

        // Parse route information
        final distanceMetersRaw = leg['distance'] ?? 0.0;
        final durationSecondsRaw = leg['duration'] ?? 0.0;
        final double distanceMeters = distanceMetersRaw is int ? distanceMetersRaw.toDouble() : distanceMetersRaw;
        final double durationSeconds = durationSecondsRaw is int ? durationSecondsRaw.toDouble() : durationSecondsRaw;
        _distance = (distanceMeters / 1000).toStringAsFixed(2) + ' km';
        final durationMinutes = (durationSeconds / 60).round();
        _duration = '$durationMinutes min';

        print('✅ Route found: Distance: $_distance, Duration: $_duration');

        // Parse route steps
        _routeSteps.clear();
        final steps = leg['steps'] as List? ?? [];
        for (var step in steps) {
          try {
            final maneuverLocation = step['maneuver']?['location'];
            final geometryCoords = step['geometry'] != null && step['geometry']['coordinates'] != null
                ? step['geometry']['coordinates'].last
                : null;

            double startLat = 0.0, startLng = 0.0, endLat = 0.0, endLng = 0.0;
            if (maneuverLocation != null && maneuverLocation.length == 2) {
              startLat = maneuverLocation[1] is int
                  ? (maneuverLocation[1] as int).toDouble()
                  : (maneuverLocation[1] as double);
              startLng = maneuverLocation[0] is int
                  ? (maneuverLocation[0] as int).toDouble()
                  : (maneuverLocation[0] as double);
            }
            if (geometryCoords != null && geometryCoords.length == 2) {
              endLat = geometryCoords[1] is int
                  ? (geometryCoords[1] as int).toDouble()
                  : (geometryCoords[1] as double);
              endLng = geometryCoords[0] is int
                  ? (geometryCoords[0] as int).toDouble()
                  : (geometryCoords[0] as double);
            } else {
              endLat = startLat;
              endLng = startLng;
            }

            final stepDistanceRaw = step['distance'] ?? 0.0;
            final stepDurationRaw = step['duration'] ?? 0.0;
            final double stepDistance = stepDistanceRaw is int
                ? (stepDistanceRaw as int).toDouble()
                : (stepDistanceRaw as double);
            final double stepDuration = stepDurationRaw is int
                ? (stepDurationRaw as int).toDouble()
                : (stepDurationRaw as double);

            _routeSteps.add(RouteStep(
              instruction: step['maneuver']?['instruction'] ?? '',
              distance: (stepDistance / 1000).toStringAsFixed(2) + ' km',
              duration: (stepDuration / 60).toStringAsFixed(0) + ' min',
              startLocation: LatLng(startLat, startLng),
              endLocation: LatLng(endLat, endLng),
            ));
          } catch (e) {
            print('⚠️ Error parsing step: $e');
          }
        }

        print('📍 Parsed ${_routeSteps.length} route steps');

        // Calculate ETA
        _calculateETA();

        // Set initial next turn instruction
        if (_routeSteps.isNotEmpty) {
          _nextTurn = _routeSteps[0].instruction;
        } else {
          _nextTurn = 'Head to destination';
        }

        print('⏰ ETA calculated: $_eta');

        // Process alternative routes
        _alternativeRoutes.clear();
        final routes = data['routes'] as List<dynamic>;
        print('🔍 Total routes in response: ${routes.length}');
        if (routes.length > 1) {
          print('✅ Processing ${routes.length - 1} alternative routes');
          for (int i = 1; i < routes.length; i++) {
            final altRoute = routes[i];
            final legs = altRoute['legs'];
            if (legs != null && legs.isNotEmpty) {
              final leg = legs[0];
              final distanceMeters = leg['distance'] ?? 0.0;
              final durationSeconds = leg['duration'] ?? 0.0;
              final distance = (distanceMeters / 1000).toStringAsFixed(2) + ' km';
              final durationMinutes = (durationSeconds / 60).round();
              final duration = '$durationMinutes min';
              _alternativeRoutes.add({
                'distance': distance,
                'duration': duration,
                'route': altRoute,
              });
              print('📍 Alternative route $i: $distance, $duration');
            }
          }
        } else {
          print('⚠️ No alternative routes found in API response, generating fallback alternatives');
          await _generateFallbackAlternatives(data);
        }
        print('📊 Final alternative routes count: ${_alternativeRoutes.length}');
      } else {
        throw Exception('No route legs found');
      }
    } catch (e) {
      print('❌ Error processing route data: $e');
      throw e;
    }
  }

  // OSRM polyline creation
  Future<void> _createPolylineOSRM(Map<String, dynamic> data) async {
    try {
      print('🗺️ Creating polyline from OSRM...');
      final route = data['routes'][0];
      final geometry = route['geometry'];
      final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];

      if (coordinates.isNotEmpty) {
        print('✅ Polyline points received: ${coordinates.length}');

        List<LatLng> polylineCoordinates = coordinates
            .map((coord) => LatLng(
                  coord[1] is int ? (coord[1] as int).toDouble() : (coord[1] as double),
                  coord[0] is int ? (coord[0] as int).toDouble() : (coord[0] as double),
                ))
            .toList();

        _polylines.clear();
        _polylines.add(
          Polyline(
            points: polylineCoordinates,
            strokeWidth: 5.0,
            color: Colors.blue,
          ),
        );

        print('✅ Polyline created successfully with ${polylineCoordinates.length} points');
      } else {
        print('⚠️ No polyline points received');
      }
    } catch (e) {
      print('❌ Error creating polyline: $e');
    }

    _notifyListeners();
  }

  // More robust ETA calculation
  void _calculateETA() {
    if (_duration.isEmpty || _duration == 'Error' || _duration == 'Unknown') {
      _eta = 'Unknown';
      return;
    }

    try {
      final now = DateTime.now();
      int totalMinutes = 0;
      
      final durationLower = _duration.toLowerCase().trim();
      
      if (durationLower.contains('hour')) {
        final hourMatch = RegExp(r'(\d+)\s*hour').firstMatch(durationLower);
        if (hourMatch != null) {
          totalMinutes += int.parse(hourMatch.group(1)!) * 60;
        }
      }
      
      if (durationLower.contains('min')) {
        final minMatch = RegExp(r'(\d+)\s*min').firstMatch(durationLower);
        if (minMatch != null) {
          totalMinutes += int.parse(minMatch.group(1)!);
        }
      }
      
      if (totalMinutes == 0) {
        final allNumbers = RegExp(r'(\d+)').allMatches(durationLower);
        final numbers = allNumbers.map((m) => int.parse(m.group(1)!)).toList();
        
        if (numbers.isNotEmpty) {
          if (durationLower.contains('hour')) {
            totalMinutes = numbers[0] * 60;
            if (numbers.length > 1) {
              totalMinutes += numbers[1];
            }
          } else {
            totalMinutes = numbers[0];
          }
        }
      }
      
      if (totalMinutes > 0) {
        final eta = now.add(Duration(minutes: totalMinutes));
        _eta = '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
      } else {
        _eta = 'Now';
      }
    } catch (e) {
      print('❌ Error calculating ETA: $e');
      _eta = 'Error';
    }
  }

  // Optimized ETA recalculation with speed (non-blocking)
  void _recalculateETAWithSpeed() {
    if (_currentSpeed == null || _currentSpeed! <= 0 || _distance.isEmpty) {
      return;
    }

    try {
      final distanceText = _distance.toLowerCase()
          .replaceAll(RegExp(r'[^\d.,]'), '')
          .replaceAll(',', '.');
      
      final distanceKm = double.tryParse(distanceText);
      
      if (distanceKm != null && distanceKm > 0) {
        final speedKmh = _currentSpeed! * 3.6;
        
        if (speedKmh > 5) {
          final timeHours = distanceKm / speedKmh;
          final timeMinutes = (timeHours * 60).round();
          
          final now = DateTime.now();
          final eta = now.add(Duration(minutes: timeMinutes));
          _eta = '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
        }
      }
    } catch (e) {
      print('❌ Error recalculating ETA with speed: $e');
    }
  }

  // Check if user is approaching next turn
  void _checkNextTurn() {
    if (_routeSteps.isEmpty || _currentStepIndex >= _routeSteps.length || _currentLocation == null) {
      return;
    }
    
    final currentStep = _routeSteps[_currentStepIndex];
    final distanceToTurn = _calculateDistance(
      LatLng(
        _currentLocation!.latitude is int ? (_currentLocation!.latitude as int).toDouble() : _currentLocation!.latitude!,
        _currentLocation!.longitude is int ? (_currentLocation!.longitude as int).toDouble() : _currentLocation!.longitude!
      ),
      currentStep.endLocation,
    );
    
    if (distanceToTurn < 0.1) {
      if (_currentStepIndex < _routeSteps.length - 1) {
        _currentStepIndex++;
        _nextTurn = _routeSteps[_currentStepIndex].instruction;
        _voiceService.speakTurnInstruction(_nextTurn);
      } else {
        _nextTurn = 'You have arrived at your destination';
        _voiceService.speakArrival();
      }
    }
    
    if (distanceToTurn < 0.5 && distanceToTurn > 0.4) {
      _voiceService.speakDistanceUpdate(_distance, _duration);
    }
  }

  void _setErrorValues() {
    _distance = 'Error';
    _duration = 'Error';
    _eta = 'Error';
    _nextTurn = 'Route unavailable';
    _notifyListeners();
  }

  // Get bounds for camera positioning
  LatLngBounds? getBounds() {
    if (_polylines.isEmpty) return null;
    final points = _polylines.first.points;
    if (points.isEmpty) return null;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (LatLng point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }

  // Switch to an alternative route
  Future<void> switchToAlternativeRoute(int index) async {
    if (index < 0 || index >= _alternativeRoutes.length) {
      print('❌ Invalid alternative route index: $index');
      return;
    }

    try {
      final altRoute = _alternativeRoutes[index]['route'] as Map<String, dynamic>;
      final legs = altRoute['legs'];
      if (legs != null && legs.isNotEmpty) {
        final leg = legs[0];

        final distanceMetersRaw = leg['distance'] ?? 0.0;
        final durationSecondsRaw = leg['duration'] ?? 0.0;
        final double distanceMeters = distanceMetersRaw is int ? distanceMetersRaw.toDouble() : distanceMetersRaw;
        final double durationSeconds = durationSecondsRaw is int ? durationSecondsRaw.toDouble() : durationSecondsRaw;
        _distance = (distanceMeters / 1000).toStringAsFixed(2) + ' km';
        final durationMinutes = (durationSeconds / 60).round();
        _duration = '$durationMinutes min';

        _routeSteps.clear();
        final steps = leg['steps'] as List? ?? [];
        for (var step in steps) {
          try {
            final maneuverLocation = step['maneuver']?['location'];
            final geometryCoords = step['geometry'] != null && step['geometry']['coordinates'] != null
                ? step['geometry']['coordinates'].last
                : null;

            double startLat = 0.0, startLng = 0.0, endLat = 0.0, endLng = 0.0;
            if (maneuverLocation != null && maneuverLocation.length == 2) {
              startLat = maneuverLocation[1] is int
                  ? (maneuverLocation[1] as int).toDouble()
                  : (maneuverLocation[1] as double);
              startLng = maneuverLocation[0] is int
                  ? (maneuverLocation[0] as int).toDouble()
                  : (maneuverLocation[0] as double);
            }
            if (geometryCoords != null && geometryCoords.length == 2) {
              endLat = geometryCoords[1] is int
                  ? (geometryCoords[1] as int).toDouble()
                  : (geometryCoords[1] as double);
              endLng = geometryCoords[0] is int
                  ? (geometryCoords[0] as int).toDouble()
                  : (geometryCoords[0] as double);
            } else {
              endLat = startLat;
              endLng = startLng;
            }

            final stepDistanceRaw = step['distance'] ?? 0.0;
            final stepDurationRaw = step['duration'] ?? 0.0;
            final double stepDistance = stepDistanceRaw is int
                ? (stepDistanceRaw as int).toDouble()
                : (stepDistanceRaw as double);
            final double stepDuration = stepDurationRaw is int
                ? (stepDurationRaw as int).toDouble()
                : (stepDurationRaw as double);

            _routeSteps.add(RouteStep(
              instruction: step['maneuver']?['instruction'] ?? '',
              distance: (stepDistance / 1000).toStringAsFixed(2) + ' km',
              duration: (stepDuration / 60).toStringAsFixed(0) + ' min',
              startLocation: LatLng(startLat, startLng),
              endLocation: LatLng(endLat, endLng),
            ));
          } catch (e) {
            print('⚠️ Error parsing step: $e');
          }
        }

        _calculateETA();

        if (_routeSteps.isNotEmpty) {
          _nextTurn = _routeSteps[0].instruction;
          _currentStepIndex = 0;
        } else {
          _nextTurn = 'Head to destination';
        }

        await _createPolylineFromRoute(altRoute);

        print('✅ Switched to alternative route $index');
        _notifyListeners();
      }
    } catch (e) {
      print('❌ Error switching to alternative route: $e');
    }
  }

  Future<void> _createPolylineFromRoute(Map<String, dynamic> route) async {
    try {
      print('🗺️ Creating polyline from alternative route...');
      final geometry = route['geometry'];
      final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];

      if (coordinates.isNotEmpty) {
        print('✅ Alternative polyline points received: ${coordinates.length}');

        List<LatLng> polylineCoordinates = coordinates
            .map((coord) => LatLng(
                  coord[1] is int ? (coord[1] as int).toDouble() : (coord[1] as double),
                  coord[0] is int ? (coord[0] as int).toDouble() : (coord[0] as double),
                ))
            .toList();

        _polylines.clear();
        _polylines.add(
          Polyline(
            points: polylineCoordinates,
            strokeWidth: 5.0,
            color: Colors.blue,
          ),
        );

        print('✅ Alternative polyline created successfully with ${polylineCoordinates.length} points');
      } else {
        print('⚠️ No alternative polyline points received');
      }
    } catch (e) {
      print('❌ Error creating alternative polyline: $e');
    }
  }

  Future<void> _generateFallbackAlternatives(Map<String, dynamic> data) async {
    try {
      print('🔄 Generating fallback alternative routes...');
      final mainRoute = data['routes'][0];
      final legs = mainRoute['legs'];

      if (legs != null && legs.isNotEmpty) {
        final leg = legs[0];
        final distanceMeters = leg['distance'] ?? 0.0;
        final durationSeconds = leg['duration'] ?? 0.0;

        final numAlternatives = math.min<int>(3, (distanceMeters / 1000).round());

        for (int i = 0; i < numAlternatives; i++) {
          final distanceVariation = (i + 1) * 0.1;
          final durationVariation = (i + 1) * 0.15;

          final altDistance = distanceMeters * (1 + distanceVariation);
          final altDuration = durationSeconds * (1 + durationVariation);

          final distance = (altDistance / 1000).toStringAsFixed(2) + ' km';
          final durationMinutes = (altDuration / 60).round();
          final duration = '$durationMinutes min';

          final simulatedRoute = {
            'distance': altDistance,
            'duration': altDuration,
            'geometry': mainRoute['geometry'],
            'legs': [{
              'distance': altDistance,
              'duration': altDuration,
              'steps': leg['steps'] ?? [],
            }],
          };

          _alternativeRoutes.add({
            'distance': distance,
            'duration': duration,
            'route': simulatedRoute,
          });

          print('📍 Generated fallback alternative ${i + 1}: $distance, $duration');
        }
      }
    } catch (e) {
      print('❌ Error generating fallback alternatives: $e');
    }
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371;

    double lat1 = point1.latitude * (math.pi / 180);
    double lat2 = point2.latitude * (math.pi / 180);
    double deltaLat = (point2.latitude - point1.latitude) * (math.pi / 180);
    double deltaLng = (point2.longitude - point1.longitude) * (math.pi / 180);

    double a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(deltaLng / 2) * math.sin(deltaLng / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }
}

// Route step model for turn-by-turn directions
class RouteStep {
  final String instruction;
  final String distance;
  final String duration;
  final LatLng startLocation;
  final LatLng endLocation;

  RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.startLocation,
    required this.endLocation,
  });
}