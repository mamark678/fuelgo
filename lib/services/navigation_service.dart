import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart'; // Add this
import 'package:location/location.dart';

import 'voice_navigation_service.dart';

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  // Navigation state
  bool _isNavigating = false;
  LatLng? _destination;
  List<Polyline> _polylines = []; // Use List<Polyline> for flutter_map
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

  // FIXED: Add debouncing and performance optimization
  Timer? _updateTimer;
  DateTime? _lastApiCall;
  static const Duration _apiCooldown = Duration(seconds: 30); // Prevent too frequent API calls
  static const Duration _updateInterval = Duration(seconds: 5); // Debounce location updates

  // Voice navigation service
  final VoiceNavigationService _voiceService = VoiceNavigationService();

  // Listeners for UI updates
  final List<Function()> _listeners = [];

  // FIXED: Add HTTP client with timeout
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

  // FIXED: Optimized listener notification
  void _notifyListeners() {
    // Use microtask to avoid blocking the main thread
    scheduleMicrotask(() {
      final listenersCopy = List<Function()>.from(_listeners);
      for (var listener in listenersCopy) {
        try {
          // Just call the listener; let the listener handle its own mounted check if needed
          listener();
        } catch (e) {
          print('Removing faulty listener due to error: $e');
          _listeners.remove(listener);
        }
      }
    });
  }

  // FIXED: Dispose method with proper cleanup
  void dispose() {
    _listeners.clear();
    _updateTimer?.cancel();
    stopNavigation();
  }

  // FIXED: Optimized location updates with debouncing
  void updateLocation(LocationData location) {
    _currentLocation = location;
    _currentSpeed = location.speed;
    
    if (_isNavigating && _destination != null) {
      // Cancel previous timer
      _updateTimer?.cancel();
      
      // Debounce updates to prevent excessive API calls
      _updateTimer = Timer(_updateInterval, () {
        _checkNextTurn();
        _recalculateETAWithSpeed();
        _notifyListeners();
      });
    } else {
      _notifyListeners();
    }
  }

  // FIXED: Improved navigation start with better error handling
  Future<void> startNavigation(LatLng destination) async {
    // Validate destination coordinates before proceeding
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
      
      // Reset all navigation state before starting
      _updateTimer?.cancel();
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

      // Always refresh current location before navigation
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
        // Instead of throwing, reset navigation and notify listeners
        _isNavigating = false;
        _destination = null;
        _polylines.clear();
        _distance = 'Error';
        _duration = 'Error';
        _eta = 'Error';
        _nextTurn = 'Unable to get current location';
        _notifyListeners();
        // Do NOT throw or rethrow here
        return;
      }
      
      // Get route with timeout
      await _getRouteToDestination();
      
      // Voice announcement for route start
      _voiceService.speakRouteStart('your destination');
      
      print('✅ Navigation started successfully');
    } catch (e) {
      print('❌ Error starting navigation: $e');
      // Reset navigation state on error
      _isNavigating = false;
      _destination = null;
      _polylines.clear();
      _distance = 'Error';
      _duration = 'Error';
      _eta = 'Error';
      _nextTurn = 'Navigation failed';
      _notifyListeners();
      // Do not rethrow, just return
      return;
    }
  }

  // Stop navigation
  void stopNavigation() {
    _updateTimer?.cancel();
    _isNavigating = false;
    _destination = null;
    _polylines.clear();
    _routeSteps.clear();
    _eta = '';
    _distance = '';
    _duration = '';
    _nextTurn = '';
    _currentStepIndex = 0;
    _lastApiCall = null; // <-- Ensure cooldown resets
    
    // Voice announcement for route end
    _voiceService.speakRouteEnd();
    
    _notifyListeners();
  }

  // FIXED: Optimized route fetching with better error handling
  Future<void> _getRouteToDestination() async {
    if (_currentLocation == null || _destination == null) {
      print('❌ Cannot get route: missing location data');
      _setErrorValues();
      return;
    }

    // FIXED: Implement API cooldown to prevent excessive calls
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
            // Defensive parsing for coordinates
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
          // Generate fallback alternative routes based on the main route
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
      // Don't throw error for polyline issues, continue with navigation
    }

    // Always notify listeners after processing
    _notifyListeners();
  }

  // FIXED: Helper method to set error values
  void _setErrorValues() {
    _distance = 'Error';
    _duration = 'Error';
    _eta = 'Error';
    _nextTurn = 'Route unavailable';
    _notifyListeners();
  }

  // Helper method to clean HTML instructions
  String _cleanHtmlInstructions(String htmlString) {
    return htmlString
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
  }

  // FIXED: More robust ETA calculation
  void _calculateETA() {
    if (_duration.isEmpty || _duration == 'Error' || _duration == 'Unknown') {
      _eta = 'Unknown';
      return;
    }

    try {
      final now = DateTime.now();
      int totalMinutes = 0;
      
      // Parse duration string with more patterns
      final durationLower = _duration.toLowerCase().trim();
      
      // Handle different duration formats
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
      
      // Handle format like "45 mins", "2 hours 30 mins"
      if (totalMinutes == 0) {
        // Try to extract just numbers followed by time units
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

  // Optimized ETA recalculation with speed
  void _recalculateETAWithSpeed() {
    if (_currentSpeed == null || _currentSpeed! <= 0 || _distance.isEmpty) {
      return;
    }

    try {
      // Extract distance in km
      final distanceText = _distance.toLowerCase()
          .replaceAll(RegExp(r'[^\d.,]'), '')
          .replaceAll(',', '.');
      
      final distanceKm = double.tryParse(distanceText);
      
      if (distanceKm != null && distanceKm > 0) {
        // Convert speed from m/s to km/h
        final speedKmh = _currentSpeed! * 3.6;
        
        if (speedKmh > 5) { // Only recalculate if moving at reasonable speed
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
    
    // If within 100 meters of turn, update next turn instruction
    if (distanceToTurn < 0.1) {
      if (_currentStepIndex < _routeSteps.length - 1) {
        _currentStepIndex++;
        _nextTurn = _routeSteps[_currentStepIndex].instruction;
        
        // Voice guidance for the turn
        _voiceService.speakTurnInstruction(_nextTurn);
      } else {
        _nextTurn = 'You have arrived at your destination';
        _voiceService.speakArrival();
      }
    }
    
    // Voice guidance for distance updates
    if (distanceToTurn < 0.5 && distanceToTurn > 0.4) {
      _voiceService.speakDistanceUpdate(_distance, _duration);
    }
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

        // Update main route data
        final distanceMetersRaw = leg['distance'] ?? 0.0;
        final durationSecondsRaw = leg['duration'] ?? 0.0;
        final double distanceMeters = distanceMetersRaw is int ? distanceMetersRaw.toDouble() : distanceMetersRaw;
        final double durationSeconds = durationSecondsRaw is int ? durationSecondsRaw.toDouble() : durationSecondsRaw;
        _distance = (distanceMeters / 1000).toStringAsFixed(2) + ' km';
        final durationMinutes = (durationSeconds / 60).round();
        _duration = '$durationMinutes min';

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

        // Recalculate ETA
        _calculateETA();

        // Set initial next turn instruction
        if (_routeSteps.isNotEmpty) {
          _nextTurn = _routeSteps[0].instruction;
          _currentStepIndex = 0;
        } else {
          _nextTurn = 'Head to destination';
        }

        // Update polyline
        await _createPolylineFromRoute(altRoute);

        print('✅ Switched to alternative route $index');
        _notifyListeners();
      }
    } catch (e) {
      print('❌ Error switching to alternative route: $e');
    }
  }

  // Create polyline from a specific route
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

  // Generate fallback alternative routes when OSRM doesn't provide them
  Future<void> _generateFallbackAlternatives(Map<String, dynamic> data) async {
    try {
      print('🔄 Generating fallback alternative routes...');
      final mainRoute = data['routes'][0];
      final legs = mainRoute['legs'];

      if (legs != null && legs.isNotEmpty) {
        final leg = legs[0];
        final distanceMeters = leg['distance'] ?? 0.0;
        final durationSeconds = leg['duration'] ?? 0.0;

        // Create 2-3 simulated alternative routes with slight variations
        final numAlternatives = math.min<int>(3, (distanceMeters / 1000).round()); // More alternatives for longer routes

        for (int i = 0; i < numAlternatives; i++) {
          // Create variations in distance and duration
          final distanceVariation = (i + 1) * 0.1; // 10%, 20%, 30% longer
          final durationVariation = (i + 1) * 0.15; // 15%, 30%, 45% longer

          final altDistance = distanceMeters * (1 + distanceVariation);
          final altDuration = durationSeconds * (1 + durationVariation);

          final distance = (altDistance / 1000).toStringAsFixed(2) + ' km';
          final durationMinutes = (altDuration / 60).round();
          final duration = '$durationMinutes min';

          // Create a simulated route object
          final simulatedRoute = {
            'distance': altDistance,
            'duration': altDuration,
            'geometry': mainRoute['geometry'], // Use same geometry for simplicity
            'legs': [{
              'distance': altDistance,
              'duration': altDuration,
              'steps': leg['steps'] ?? [], // Use same steps
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

  // Calculate distance between two points (Haversine formula)
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // Earth's radius in kilometers

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