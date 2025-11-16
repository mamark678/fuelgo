import 'package:flutter/material.dart';

import 'models/gas_station.dart';
import 'screens/for_you_screen.dart';
import 'screens/list_screen.dart';
import 'screens/map_tab.dart';
import 'screens/profile_screen.dart';
import 'services/debug_service.dart';
import 'services/gas_station_service.dart';
import 'services/navigation_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // Start with Maps tab
  final NavigationService _navigationService = NavigationService();
  bool _isLoading = true;
  String _error = '';

  late final GlobalKey<ListScreenState> _listScreenKey = GlobalKey<ListScreenState>();
  late final List<Widget> _screens;

  void switchToListTabAndShowStation(GasStation station) {
    setState(() {
      _currentIndex = 2; // Switch to List tab
    });
    // Use addPostFrameCallback to ensure the tab switch is complete before showing details
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Extract stationId from the GasStation object
      final stationId = station.id ?? station.name ?? '';
      _listScreenKey.currentState?.showStationDetails(stationId);
    });
  }

  void switchToListTabAndShowStationById(String stationId) {
    setState(() {
      _currentIndex = 2; // Switch to List tab
    });
    // Use addPostFrameCallback to ensure the tab switch is complete before showing details
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listScreenKey.currentState?.showStationDetails(stationId);
    });
  }

  @override
  void initState() {
    super.initState();
    _screens = [
      ForYouScreen(onNavigateToStation: switchToListTabAndShowStationById),
      MapTab(assignedStations: [], onNavigateToStation: switchToListTabAndShowStation),
      ListScreen(key: _listScreenKey),
      const ProfileScreen(),
    ];
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Fetch data first
      await GasStationService.fetchAndCacheGasStations(forceRefresh: true);
      
      // Then initialize other services
    _navigationService.addListener(_onNavigationChanged);
      await _navigationService.initializeVoiceNavigation();
      print('Voice navigation initialized');

    } catch (e) {
      print('Initialization failed: $e');
      setState(() {
        _error = 'Failed to load station data. Please restart the app.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshData() async {
    try {
      setState(() {
        _error = '';
      });

      // Refresh gas station data
      await GasStationService.fetchAndCacheGasStations(forceRefresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data refreshed successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Refresh failed: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to refresh data. Please try again.';
        });
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

  @override
  void dispose() {
    _navigationService.removeListener(_onNavigationChanged);
    super.dispose();
  }

  void _onNavigationChanged() {
    // Removed automatic tab switching - let users stay on their current tab
    // Users can manually switch to Maps tab if they want to see navigation
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Finding gas stations...'),
          ],
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refreshData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: _screens[_currentIndex],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
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
            icon: Icon(Icons.favorite),
            label: 'For You',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Maps',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'List',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
