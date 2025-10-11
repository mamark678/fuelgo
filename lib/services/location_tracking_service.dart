import 'dart:async';

import 'package:location/location.dart';

class LocationTrackingService {
  Location? _location;
  bool _isTracking = false;
  bool _isDisposed = false;
  StreamSubscription<LocationData>? _locationSubscription;
  
  // Location tracking mode
  bool _isNavigationMode = false;
  
  LocationTrackingService() {
    _location = Location();
    _initializeLocation();
  }
  
  Future<void> _initializeLocation() async {
    if (_location == null) return;
    
    try {
      bool serviceEnabled = await _location!.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location!.requestService();
        if (!serviceEnabled) {
          throw Exception('Location services are disabled');
        }
      }
      
      PermissionStatus permissionGranted = await _location!.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location!.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          throw Exception('Location permissions are denied');
        }
      }
    } catch (e) {
      print('Error initializing location: $e');
    }
  }
  
  /// Start continuous location tracking
  Future<void> startTracking() async {
    if (_isDisposed || _isTracking) return;
    
    try {
      await _initializeLocation();
      
      _locationSubscription = _location!.onLocationChanged.listen(
        (LocationData currentLocation) {
          // Handle location updates
          if (!_isDisposed) {
            // You can add location update handling here if needed
          }
        },
        onError: (error) {
          print('Location tracking error: $error');
        },
      );
      
      _isTracking = true;
      print('Location tracking started');
    } catch (e) {
      print('Error starting location tracking: $e');
      throw Exception('Failed to start location tracking: $e');
    }
  }
  
  /// Stop location tracking
  Future<void> stopTracking() async {
    if (!_isTracking || _isDisposed) return;
    
    try {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      _isTracking = false;
      print('Location tracking stopped');
    } catch (e) {
      print('Error stopping location tracking: $e');
    }
  }
  
  /// Enable high accuracy mode for navigation
  Future<void> enableNavigationMode() async {
    if (_isDisposed) return;
    
    try {
      _isNavigationMode = true;
      if (_location != null) {
        await _location!.changeSettings(
          accuracy: LocationAccuracy.high,
          interval: 1000, // 1 second updates
          distanceFilter: 0, // Update on every change
        );
      }
      print('Navigation mode enabled');
    } catch (e) {
      print('Error enabling navigation mode: $e');
    }
  }
  
  /// Enable normal mode for regular location updates
  Future<void> enableNormalMode() async {
    if (_isDisposed) return;
    
    try {
      _isNavigationMode = false;
      if (_location != null) {
        await _location!.changeSettings(
          accuracy: LocationAccuracy.balanced,
          interval: 5000, // 5 second updates
          distanceFilter: 10, // Update every 10 meters
        );
      }
      print('Normal mode enabled');
    } catch (e) {
      print('Error enabling normal mode: $e');
    }
  }
  
  /// Get current location
  Future<LocationData?> getCurrentLocation() async {
    if (_isDisposed) return null;
    
    try {
      await _initializeLocation();
      return await _location!.getLocation();
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }
  
  /// Check if location tracking is active
  bool get isTracking => _isTracking;
  
  /// Check if navigation mode is enabled
  bool get isNavigationMode => _isNavigationMode;
  
  /// Clean up resources
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    try {
      await stopTracking();
      _location = null;
      _isDisposed = true;
      print('LocationTrackingService disposed');
    } catch (e) {
      print('Error disposing LocationTrackingService: $e');
    }
  }
}
