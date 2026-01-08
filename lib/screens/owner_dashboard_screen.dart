import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'amenities_tab.dart';
import 'manage_prices_screen.dart';
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
        
        final stations = await FirestoreService.getGasStationsByOwner(user.uid);
        
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
    final theme = Theme.of(context);
    final gradientTheme = theme.extension<GradientTheme>()!;

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: theme.primaryColor,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Owner Dashboard'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: gradientTheme.primaryGradient,
          ),
        ),
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
        color: theme.primaryColor,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _screens[_currentIndex],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: Colors.white,
          indicatorColor: theme.primaryColor.withOpacity(0.2),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: 'Amenities',
            ),
            NavigationDestination(
              icon: Icon(Icons.flash_on_outlined),
              selectedIcon: Icon(Icons.flash_on),
              label: 'Offers',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_gas_station_outlined),
              selectedIcon: Icon(Icons.local_gas_station),
              label: 'Prices',
            ),
          ],
        ),
      ),
    );
  }
}