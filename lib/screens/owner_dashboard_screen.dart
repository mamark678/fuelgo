import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'amenities_tab.dart';
import 'manage_prices_screen.dart'; // Import your price management screen
import 'map_tab.dart';
import 'offers_tab.dart';
import 'station_dashboard_tab.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => OwnerDashboardScreenState();
}

class OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  int _currentIndex = 0;
  String? _userEmail;
  String? _userId;
  bool _isLoading = true;
  List<Map<String, dynamic>> _assignedStations = [];

  List<Widget> get _screens => [
    StationDashboardTab(assignedStations: _assignedStations, userId: _userId),
    MapTab(assignedStations: _assignedStations),
    AmenitiesTab(assignedStations: _assignedStations),
    const OffersTab(),
    // Add price management as a tab (temporary for testing)
    _assignedStations.isNotEmpty 
        ? ManagePricesScreen(station: _assignedStations.first)
        : const Center(child: Text('No stations available')),
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = AuthService().currentUser;
      if (user != null) {
        setState(() {
          _userEmail = user.email;
          _userId = user.uid;
        });
        
        print('Loading stations for user: ${user.uid}');
        
        // Load assigned stations
        final stations = await FirestoreService.getGasStationsByOwner(user.uid);
        print('🔍 DEBUG: Raw stations data: $stations');
        print('🔍 DEBUG: Stations structure: ${stations.map((s) => s.keys.toList())}');

        for (final station in stations) {
          print('🔍 DEBUG: Station data: $station');
          print('🔍 DEBUG: Station prices: ${station['prices']}');
          print('🔍 DEBUG: Station position: ${station['position']}');
          print('🔍 DEBUG: Station amenities: ${station['amenities']}');
        }
        
        setState(() {
          _assignedStations = stations;
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> refreshDashboard() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      await _loadUserData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dashboard refreshed successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Refresh failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _signOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut == true) {
      try {
        // Sign out from Firebase Auth
        await AuthService().signOut();
        
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/role-selection');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error signing out: $e')),
          );
        }
      }
    }
  }

  

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () {
              Navigator.pushNamed(context, '/analytics');
            },
            tooltip: 'Analytics',
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              if (_userId == null || _userId!.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Owner information not available yet.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pushNamed(
                context,
                '/gas-price-history',
                arguments: {
                  'ownerId': _userId!,
                  'assignedStations': _assignedStations,
                },
              );
            },
            tooltip: 'Gas Prices History',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refreshDashboard,
        child: _screens[_currentIndex],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront),
            label: 'Amenities',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.flash_on),
            label: 'Offers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_gas_station),
            label: 'Prices',
          ),
        ],
      ),
    );
  }
}