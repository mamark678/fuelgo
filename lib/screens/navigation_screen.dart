import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

import '../models/gas_station.dart';
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
  final Location _locationService = Location();
  
  StreamSubscription<LocationData>? _locationSubscription;
  bool _isInitialized = false;
  bool _isNavigating = false;
  bool _voiceEnabled = true;
  String _navigationStartTime = '';
  String _navigationEndTime = '';

  @override
  void initState() {
    super.initState();
    _initializeNavigation();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _navigationService.removeListener(_onNavigationUpdate);
    super.dispose();
  }

  Future<void> _initializeNavigation() async {
    try {
      // Initialize voice navigation
      await _navigationService.initializeVoiceNavigation();
      
      // Add listener for navigation updates
      _navigationService.addListener(_onNavigationUpdate);
      
      // Request location permission
      final permission = await _locationService.requestPermission();
      if (permission == PermissionStatus.granted) {
        // Start location updates
        _locationSubscription = _locationService.onLocationChanged.listen((location) {
          _navigationService.updateLocation(location);
        });
        
        // Get initial location
        final initialLocation = await _locationService.getLocation();
        _navigationService.updateLocation(initialLocation);
        
        setState(() {
          _isInitialized = true;
        });
      } else {
        _showErrorDialog('Location permission is required for navigation');
      }
    } catch (e) {
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
      await _navigationService.startNavigation(widget.destination.position);
      setState(() {
        _isNavigating = true;
      });
    } catch (e) {
      _showErrorDialog('Failed to start navigation: $e');
    }
  }

  void _stopNavigation() {
    _navigationEndTime = _formatTime(DateTime.now());
    _navigationService.stopNavigation();
    setState(() {
      _isNavigating = false;
    });
    
    // Show navigation details
    _showNavigationDetails();
  }

  void _toggleVoiceNavigation() {
    setState(() {
      _voiceEnabled = !_voiceEnabled;
    });
    _voiceService.setEnabled(_voiceEnabled);
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
            child: FlutterMap(
              options: MapOptions(
                initialCenter: widget.destination.position,
                initialZoom: 15.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
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
                
                // Current location marker
                if (_navigationService.currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          _navigationService.currentLocation!.latitude!,
                          _navigationService.currentLocation!.longitude!,
                        ),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
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
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(
                          Icons.place,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Navigation Controls
          Container(
            padding: const EdgeInsets.all(16),
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
