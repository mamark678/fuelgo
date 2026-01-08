import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'models/gas_station.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/for_you_screen.dart';
import 'screens/list_screen.dart';
import 'screens/map_tab.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
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

  late final GlobalKey<ListScreenState> _listScreenKey =
      GlobalKey<ListScreenState>();
  late final GlobalKey<ForYouScreenState> _forYouScreenKey =
      GlobalKey<ForYouScreenState>();
  late final List<Widget> _screens;

  void switchToListTabAndShowStation(GasStation station) {
    setState(() {
      _currentIndex = 2; // Switch to List tab
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stationId = station.id ?? station.name ?? '';
      _listScreenKey.currentState?.showStationDetails(stationId);
    });
  }

  void switchToListTabAndShowStationById(String stationId) {
    setState(() {
      _currentIndex = 2; // Switch to List tab
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listScreenKey.currentState?.showStationDetails(stationId);
    });
  }

  @override
  void initState() {
    super.initState();
    _screens = [
      ForYouScreen(
          key: _forYouScreenKey,
          onNavigateToStation: switchToListTabAndShowStationById),
      MapTab(
          assignedStations: [],
          onNavigateToStation: switchToListTabAndShowStation),
      ListScreen(key: _listScreenKey),
      const ProfileScreen(),
    ];
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await GasStationService.fetchAndCacheGasStations(forceRefresh: true);

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
    // Navigation logic
  }

  String _getTitle() {
    switch (_currentIndex) {
      case 0:
        return 'For You';
      case 1:
        return 'Maps';
      case 2:
        return 'Gas Stations';
      case 3:
        return 'Profile';
      default:
        return 'Fuel-GO!';
    }
  }

  void _openNotifications() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );

    if (result != null && result is Map<String, dynamic>) {
      final highlightItemId = result['highlightItemId'] as String?;
      final highlightType = result['highlightType'] as String?;
      final tabIndex = result['tabIndex'] as int?;

      if (highlightItemId != null &&
          highlightType != null &&
          tabIndex != null) {
        setState(() {
          _currentIndex = tabIndex;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _forYouScreenKey.currentState?.highlightItem(
            itemId: highlightItemId,
            type: highlightType,
          );
        });
      }
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 16),
            const Text('Finding gas stations...'),
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
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
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
      color: Theme.of(context).primaryColor,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _screens[_currentIndex],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _getTitle(),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('read', isEqualTo: false)
                .limit(1)
                .snapshots(),
            builder: (context, snapshot) {
              final hasUnread =
                  snapshot.hasData && snapshot.data!.docs.isNotEmpty;
              return IconButton(
                icon: Badge(
                  isLabelVisible: hasUnread,
                  backgroundColor: Colors.red,
                  smallSize: 10,
                  alignment: Alignment.topLeft,
                  child: const Icon(Icons.notifications),
                ),
                onPressed: _openNotifications,
                tooltip: 'Notifications',
              );
            },
          ),
          if (_currentIndex == 3)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Profile',
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EditProfileScreen(),
                  ),
                );
                if (result == true && mounted) {
                  setState(() {});
                }
              },
            ),
        ],
      ),
      body: _buildBody(),
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
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite),
              label: 'For You',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Maps',
            ),
            NavigationDestination(
              icon: Icon(Icons.list_alt),
              selectedIcon: Icon(Icons.list),
              label: 'List',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
