import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/gas_station.dart';
import '../services/location_tracking_service.dart'; // Add this import
import '../services/navigation_service.dart';
import '../services/voice_navigation_service.dart';
import 'navigation_details_screen.dart';

class NavigationScreen extends StatefulWidget {
  final GasStation destination;

  const NavigationScreen({
    super.key,
    required this.destination,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final NavigationService _navigationService = NavigationService();
  final VoiceNavigationService _voiceService = VoiceNavigationService();
  final LocationTrackingService _trackingService = LocationTrackingService(); // NEW: Use tracking service
  final MapController _mapController = MapController(); // NEW: For auto-centering
  
  bool _isInitialized = false;
  bool _isNavigating = false;
  bool _voiceEnabled = true;
  bool _autoCenter = true; // NEW: Auto-center map on user location
  bool _isMapLocked = true;
  String _navigationStartTime = '';
  String _navigationEndTime = '';

  @override
  void initState() {
    super.initState();
    _initializeNavigation();
  }

  @override
  void dispose() {
    _trackingService.dispose(); // Clean up tracking service
    _navigationService.removeListener(_onNavigationUpdate);
    super.dispose();
  }

  Future<void> _initializeNavigation() async {
    try {
      // Initialize voice navigation
      await _navigationService.initializeVoiceNavigation();
      
      // Add listener for navigation updates
      _navigationService.addListener(_onNavigationUpdate);
      
      // NEW: Start real-time location tracking with callback
      await _trackingService.startTracking(
        onUpdate: (locationData) {
          // Forward location to navigation service immediately
          _navigationService.updateLocation(locationData);
          
          // Auto-center map on user location if enabled
          if (_autoCenter && mounted && _isNavigating) {
            try {
              _mapController.move(
                LatLng(locationData.latitude!, locationData.longitude!),
                _mapController.camera.zoom,
              );
            } catch (e) {
              // Ignore map controller errors during disposal
            }
          }
          
          // Update UI
          if (mounted) {
            setState(() {});
          }
        },
      );
      
      // Enable high accuracy mode for navigation
      await _trackingService.enableNavigationMode();
      
      // Get initial location
      final initialLocation = await _trackingService.getCurrentLocation();
      if (initialLocation != null) {
        _navigationService.updateLocation(initialLocation);
      }
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      print('❌ Error initializing navigation: $e');
      _showErrorDialog('Failed to initialize navigation: $e');
    }
  }

  void _onNavigationUpdate() {
    if (mounted) {
      setState(() {
        _isNavigating = _navigationService.isNavigating;
      });
    }
  }

  Future<void> _startNavigation() async {
    try {
      _navigationStartTime = _formatTime(DateTime.now());
      
      // Ensure we're in high accuracy mode
      await _trackingService.enableNavigationMode();
      
      // Start navigation
      await _navigationService.startNavigation(widget.destination.position);
      
      setState(() {
        _isNavigating = true;
        _autoCenter = true; // Enable auto-centering when navigation starts
      });
      
      // Fit map to show route
      _fitMapToRoute();
    } catch (e) {
      print('❌ Error starting navigation: $e');
      _showErrorDialog('Failed to start navigation: $e');
    }
  }

  void _stopNavigation() {
    _navigationEndTime = _formatTime(DateTime.now());
    _navigationService.stopNavigation();
    
    // Switch back to normal tracking mode
    _trackingService.enableNormalMode();
    
    setState(() {
      _isNavigating = false;
      _autoCenter = false;
    });
    
    // Show navigation details
    _showNavigationDetails();
  }

  void _toggleVoiceNavigation() {
    setState(() {
      _voiceEnabled = !_voiceEnabled;
    });
    _navigationService.setVoiceEnabled(_voiceEnabled);
  }

  void _toggleAutoCenter() {
    setState(() {
      _autoCenter = !_autoCenter;
    });
  }

  void _centerOnCurrentLocation() {
    if (_navigationService.currentLocation != null) {
      _mapController.move(
        LatLng(
          _navigationService.currentLocation!.latitude!,
          _navigationService.currentLocation!.longitude!,
        ),
        18.0,
      );
      setState(() {
    _isMapLocked = true; // Lock map by default when navigation starts
  });
    }
  }

  void _fitMapToRoute() {
    if (_navigationService.polylines.isNotEmpty) {
      final bounds = _navigationService.getBounds();
      if (bounds != null) {
        try {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(50),
            ),
          );
        } catch (e) {
          print('⚠️ Error fitting map to route: $e');
        }
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Navigation Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _showNavigationDetails() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NavigationDetailsScreen(
          destination: widget.destination,
          totalDistance: _navigationService.distance,
          totalDuration: _navigationService.duration,
          startTime: _navigationStartTime,
          endTime: _navigationEndTime,
          routeSteps: _navigationService.routeSteps,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Initializing Navigation'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Setting up navigation...'),
              SizedBox(height: 8),
              Text(
                'Enabling high-accuracy GPS...',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Navigate to ${widget.destination.name}'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_voiceEnabled ? Icons.volume_up : Icons.volume_off),
            onPressed: _toggleVoiceNavigation,
            tooltip: _voiceEnabled ? 'Disable Voice' : 'Enable Voice',
          ),
          if (_isNavigating)
            IconButton(
              icon: Icon(_autoCenter ? Icons.gps_fixed : Icons.gps_not_fixed),
              onPressed: _toggleAutoCenter,
              tooltip: _autoCenter ? 'Disable Auto-Center' : 'Enable Auto-Center',
            ),
        ],
      ),
      body: Column(
        children: [
          // Navigation Status Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _isNavigating ? Colors.green.shade50 : Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isNavigating ? Icons.navigation : Icons.location_on,
                      color: _isNavigating ? Colors.green : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isNavigating ? 'Navigating' : 'Ready to Navigate',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _isNavigating ? Colors.green : Colors.blue,
                      ),
                    ),
                    const Spacer(),
                    // NEW: Real-time indicator
                    if (_trackingService.isTracking)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green, width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'LIVE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isNavigating) ...[
                  _buildNavigationInfo(),
                ] else ...[
                  Text(
                    'Tap "Start Navigation" to begin turn-by-turn directions',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
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
                    initialCenter: widget.destination.position,
                    initialZoom: 15.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                    onPositionChanged: (position, hasGesture) {
                      // Disable auto-center if user manually moves map
                      if (hasGesture && _autoCenter) {
                        setState(() {
                          _autoCenter = false;
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName: 'com.fuelgo.app',
                    ),
                    
                    // Navigation polylines
                    if (_navigationService.polylines.isNotEmpty)
                      PolylineLayer(
                        polylines: _navigationService.polylines,
                      ),
                    
                    // Current location marker (animated in real-time)
                    if (_navigationService.currentLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                              _navigationService.currentLocation!.latitude!,
                              _navigationService.currentLocation!.longitude!,
                            ),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.3),
                                    blurRadius: 8,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.navigation,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    
                    // Destination marker
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: widget.destination.position,
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.destination.name ?? 'Destination',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.place,
                                color: Colors.red,
                                size: 40,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                
                // Floating action buttons
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    children: [
                      // Center on location button
                      FloatingActionButton(
                        heroTag: 'center',
                        mini: true,
                        backgroundColor: Colors.white,
                        onPressed: _centerOnCurrentLocation,
                        child: const Icon(Icons.my_location, color: Colors.blue),
                      ),
                      const SizedBox(height: 8),
                      // Fit to route button
                      if (_isNavigating)
                        FloatingActionButton(
                          heroTag: 'fit',
                          mini: true,
                          backgroundColor: Colors.white,
                          onPressed: _fitMapToRoute,
                          child: const Icon(Icons.fit_screen, color: Colors.blue),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Navigation Controls
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isNavigating ? _stopNavigation : _startNavigation,
                    icon: Icon(_isNavigating ? Icons.stop : Icons.navigation),
                    label: Text(_isNavigating ? 'Stop Navigation' : 'Start Navigation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isNavigating ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Close'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationInfo() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildInfoItem(
              'Distance',
              _navigationService.distance,
              Icons.straighten,
              Colors.blue,
            ),
            _buildInfoItem(
              'Duration',
              _navigationService.duration,
              Icons.access_time,
              Colors.orange,
            ),
            _buildInfoItem(
              'ETA',
              _navigationService.eta,
              Icons.schedule,
              Colors.green,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_navigationService.currentSpeed != null && _navigationService.currentSpeed! > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speed, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '${(_navigationService.currentSpeed! * 3.6).toStringAsFixed(0)} km/h',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (_navigationService.nextTurn.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.turn_right, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _navigationService.nextTurn,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}