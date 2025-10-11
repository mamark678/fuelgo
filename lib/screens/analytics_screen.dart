import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';
import 'package:fuelgo/services/analytics_service.dart';
import 'package:fuelgo/services/auth_service.dart';
import 'package:fuelgo/services/firestore_service.dart';
import 'package:fuelgo/services/user_preferences_service.dart';
import 'package:fuelgo/widgets/analytics_card_widget.dart';
import 'package:fuelgo/widgets/analytics_summary_widget.dart';
import 'package:fuelgo/widgets/market_trends_chart_widget.dart';
import 'package:fuelgo/widgets/price_chart_widget.dart';
import 'package:fuelgo/widgets/station_selector_widget.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final List<String> _timePeriods = ['7 days', '30 days', '90 days'];
  String _selectedTimePeriod = '30 days';
  String? _selectedStationId;
  String? _selectedFuelType;
  List<AnalyticsData> _analyticsData = [];
  bool _isLoading = false;
  AnalyticsData? _selectedAnalytics;
  int _selectedTabIndex = 0;
  AnalyticsData? _selectedStationAnalytics; // For detailed price history
  bool _isLoadingStationAnalytics = false;
  String _searchQuery = '';
  int _stationListReloadKey = 0;
  Future<List<Map<String, dynamic>>>? _stationsFuture;
  final UserPreferencesService _prefsService = UserPreferencesService();

  // Ratings data structure: stationId => { userId: { name, rating, comment } }
  Map<String, Map<String, Map<String, dynamic>>> _ratings = {};
  StreamSubscription<QuerySnapshot>? _ratingsSubscription;

  @override
  void initState() {
    super.initState();
    _selectedFuelType = null; // Initialize to 'regular' to load analytics immediately
    _stationsFuture = FirestoreService.getAllGasStations();
    _initializeDefaultTab();
    _loadAnalyticsData();
    _setupRatingsRealtimeListener();
  }

  Future<void> _initializeDefaultTab() async {
    try {
      final user = AuthService().currentUser;
      if (user != null) {
        // Check user role from Firestore
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data() as Map<String, dynamic>;
          final userRole = userData['role'] ?? 'customer';

          // If user is an owner, default to Market Trends tab
          if (userRole == 'owner') {
            setState(() {
              _selectedTabIndex = 1; // Market Trends tab
            });
          }
        }
      }
    } catch (e) {
      print('Error checking user role: $e');
      // Default to My Analytics tab if error
    }
  }

  @override
  void dispose() {
    _ratingsSubscription?.cancel();
    super.dispose();
  }

  void _setupRatingsRealtimeListener() {
    _ratingsSubscription = FirebaseFirestore.instance.collection('station_ratings').snapshots().listen((snapshot) {
      // Build map: stationId => { userId: { name, rating, comment } }
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
        };
      }

      // Update local cache & storage
      _ratings = rebuilt;

      // Recompute UI station ratings by reloading gas stations (simple and safe)
      _loadAnalyticsData();
    }, onError: (err) {
      debugPrint('Ratings listener error: $err');
    });
  }

  Future<void> _loadAnalyticsData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = AuthService().currentUser;
      if (user != null) {
        final daysBack = _getDaysBackFromPeriod(_selectedTimePeriod);
        
        List<AnalyticsData> analytics;
        if (_selectedTabIndex == 0) { // Owner analytics
          analytics = await AnalyticsService.getOwnerAnalytics(
            ownerId: user.uid,
            fuelType: _selectedFuelType,
            daysBack: daysBack,
          );
        } else { // Market trends
          analytics = await AnalyticsService.getMarketTrends(
            fuelType: _selectedFuelType,
            daysBack: daysBack,
          );
        }

        setState(() {
          _analyticsData = analytics;
          if (analytics.isNotEmpty && _selectedAnalytics == null) {
            _selectedAnalytics = analytics.first;
          }
          // Reset selected station analytics when main analytics data changes
          _selectedStationAnalytics = null;
          _selectedStationId = null;
        });
      } else {
        // User is not authenticated, clear analytics data
        setState(() {
          _analyticsData = [];
          _selectedAnalytics = null;
          _selectedStationAnalytics = null;
          _selectedStationId = null;
        });
      }
    } catch (e) {
      // Handle error - check if it's a permission denied error
      if (e.toString().contains('PERMISSION_DENIED') || e.toString().contains('Missing or insufficient permissions')) {
        // User is likely logged out, clear analytics data
        setState(() {
          _analyticsData = [];
          _selectedAnalytics = null;
          _selectedStationAnalytics = null;
          _selectedStationId = null;
        });
      } else {
        print('Error loading analytics: $e');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  int _getDaysBackFromPeriod(String period) {
    switch (period) {
      case '7 days':
        return 7;
      case '30 days':
        return 30;
      case '90 days':
        return 90;
      default:
        return 30;
    }
  }

  Future<void> _loadStationAnalytics(String stationId, String? fuelType) async {
    setState(() {
      _isLoadingStationAnalytics = true;
    });

    try {
      final daysBack = _getDaysBackFromPeriod(_selectedTimePeriod);
      final station = await FirestoreService.getGasStation(stationId);
      if (station != null) {
        print('DEBUG: Station data retrieved: $station');
        print('DEBUG: Station prices: ${station['prices']}');
        print('DEBUG: Fuel type being queried: $fuelType');

        final stationName = station['name']?.toString() ?? 'Unknown Station';
        final analytics = await AnalyticsService.getStationAnalytics(
          stationId: stationId,
          stationName: stationName,
          fuelType: fuelType,
          daysBack: daysBack,
        );

        setState(() {
          _selectedStationAnalytics = analytics;
          _selectedStationId = stationId;
        });
      } else {
        print('DEBUG: No station found with ID: $stationId');
      }
    } catch (e) {
      print('Error loading station analytics: $e');
    } finally {
      setState(() {
        _isLoadingStationAnalytics = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isUserOwner(),
      builder: (context, snapshot) {
        final isOwner = snapshot.data ?? false;

        if (isOwner) {
          // For owners, show only Market Trends
          return Scaffold(
            appBar: AppBar(
              title: const Text('Analytics'),
            ),
            body: _buildMarketTrendsTab(),
          );
        } else {
          // For regular users, show both tabs
          return DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Analytics'),
                bottom: TabBar(
                  tabs: const [
                    Tab(text: 'My Analytics'),
                    Tab(text: 'Market Trends'),
                  ],
                  onTap: (index) {
                    setState(() {
                      _selectedTabIndex = index;
                    });
                    _loadAnalyticsData();
                  },
                ),
              ),
              body: TabBarView(
                children: [
                  _buildAnalyticsTab(),
                  _buildMarketTrendsTab(),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Future<bool> _isUserOwner() async {
    try {
      final user = AuthService().currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data() as Map<String, dynamic>;
          final userRole = userData['role'] ?? 'customer';
          return userRole == 'owner';
        }
      }
    } catch (e) {
      print('Error checking user role: $e');
    }
    return false;
  }

  Widget _buildAnalyticsTab() {
    final user = AuthService().currentUser;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.blue,
                child: Icon(
                  Icons.analytics,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Price Analytics',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Detailed price analysis for your stations',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Analytics Summary Section
        AnalyticsSummaryWidget(
          analyticsData: _analyticsData,
          isLoading: _isLoading,
        ),

        const SizedBox(height: 24),

        // Price History Chart
        if (_selectedStationAnalytics != null)
          PriceChartWidget(
            analyticsData: _selectedStationAnalytics!,
            chartHeight: 250,
            showTitle: true,
          )
        else if (_isLoadingStationAnalytics)
          const Center(child: CircularProgressIndicator())
        else
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Select a gas station below to view price history',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),

        const SizedBox(height: 24),

        // Gas Station Selection Below Chart
        if (user != null && _selectedTabIndex == 0)
          _buildStationListWidget(user.uid),

        const SizedBox(height: 16),

        // Time Period Selector
        _buildTimePeriodSelector(),

        const SizedBox(height: 16),

        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_analyticsData.isEmpty)
          const Center(child: Text('No analytics data available'))
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: _analyticsData.map((analytics) => AnalyticsCardWidget(
              analyticsData: analytics,
              onTap: () {
                setState(() {
                  _selectedAnalytics = analytics;
                });
              },
              isSelected: _selectedAnalytics?.stationId == analytics.stationId &&
                         _selectedAnalytics?.fuelType == analytics.fuelType,
              compact: true,
            )).toList(),
          ),
      ],
    );
  }

  Widget _buildStationListWidget(String ownerId) {
    Map<String, double> _normalizePricesMap(Map<String, dynamic> prices) {
      final Map<String, double> normalized = {};
      prices.forEach((key, value) {
        final normalizedKey = key.toLowerCase();
        final price = (value as num).toDouble();
        if (!normalized.containsKey(normalizedKey) || price < normalized[normalizedKey]!) {
          normalized[normalizedKey] = price;
        }
      });
      return normalized;
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_stationListReloadKey),
      future: _stationsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return const Center(child: Text('Error loading stations'));
        }

        final allStations = snapshot.data ?? [];
        print('DEBUG ANALYTICS: Total stations loaded: ${allStations.length}');
        for (var i = 0; i < allStations.length; i++) {
          final station = allStations[i];
          print('DEBUG ANALYTICS: Station ${i + 1}: ID=${station['id']}, Name=${station['name']}, Brand=${station['brand']}');
        }

        final filteredStations = _searchQuery.isEmpty
            ? allStations
            : allStations.where((station) {
                final name = (station['name'] ?? '').toLowerCase();
                final brand = (station['brand'] ?? '').toLowerCase();
                final query = _searchQuery.toLowerCase();
                return name.contains(query) || brand.contains(query);
              }).toList();

        print('DEBUG ANALYTICS: Filtered stations count: ${filteredStations.length}');

        if (allStations.isEmpty) {
          return const Center(child: Text('No gas stations found'));
        }

        // Collect all normalized fuel types from all stations for dropdown
        final Set<String> allFuelTypes = {};
        for (final station in filteredStations) {
          final prices = station['prices'] as Map<String, dynamic>? ?? {};
          final normalizedPrices = _normalizePricesMap(prices);
          allFuelTypes.addAll(normalizedPrices.keys);
        }
        final sortedFuelTypes = allFuelTypes.toList()..sort();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Select Gas Station for Price History',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search gas stations...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                onSubmitted: (value) {
                  // Removed reload on Enter as per user request
                },
              ),
            ),
            // Station List
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredStations.length,
              itemBuilder: (context, index) {
                final station = filteredStations[index];
                return _buildGasStationTile(station);
              },
            ),
            // Fuel Type Selection
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<String>(
                value: _selectedFuelType != null ? _selectedFuelType!.toLowerCase() : null,
                decoration: const InputDecoration(
                  labelText: 'Select Fuel Type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All Fuel Types'),
                  ),
                  ...sortedFuelTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.toUpperCase()),
                    );
                  }).toList(),
                ],
                onChanged: (fuelType) {
                  setState(() {
                    _selectedFuelType = fuelType;
                    if (_selectedStationId != null) {
                      _loadStationAnalytics(_selectedStationId!, fuelType);
                    } else {
                      _selectedStationAnalytics = null;
                    }
                  });
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGasStationTile(Map<String, dynamic> station) {
    final stationId = station['id']?.toString();
    final stationName = station['name']?.toString() ?? 'Unknown Station';
    final brand = station['brand']?.toString() ?? '';
    final pricesRaw = station['prices'] as Map<String, dynamic>? ?? {};
    final prices = <String, double>{};
    pricesRaw.forEach((key, value) {
      final normalizedKey = key.toLowerCase();
      final price = (value as num).toDouble();
      if (!prices.containsKey(normalizedKey) || price < prices[normalizedKey]!) {
        prices[normalizedKey] = price;
      }
    });
    final isSelected = _selectedStationId == stationId;

    // Get marker color based on brand
    final markerColor = _getMarkerColor(brand);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      elevation: isSelected ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedStationId = stationId;
            if (stationId != null) {
              _loadStationAnalytics(stationId, _selectedFuelType);
            } else {
              _selectedStationAnalytics = null;
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(markerColor).withOpacity(0.2),
                    child: Text(
                      (brand.isNotEmpty ? brand[0] : 'G').toUpperCase(),
                      style: TextStyle(
                        color: Color(markerColor),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stationName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          brand,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildRatingStars(_calculateAverageRating(_ratings[station['id'] ?? ''])),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Open',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _prefsService.isFavorite(station['id'] ?? '') ? Icons.favorite : Icons.favorite_border,
                          color: _prefsService.isFavorite(station['id'] ?? '') ? Colors.red : Colors.grey,
                          size: 20,
                        ),
                        onPressed: () {
                          _prefsService.toggleFavoriteStation(station['id'] ?? '');
                          setState(() {});
                        },
                        tooltip: _prefsService.isFavorite(station['id'] ?? '') ? 'Remove from favorites' : 'Add to favorites',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      // Removed navigate button as per request
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₱${_selectedFuelType != null && prices[_selectedFuelType!.toLowerCase()] != null ? prices[_selectedFuelType!.toLowerCase()]!.toStringAsFixed(2) : 'N/A'}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const Text(
                        '/L',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatingStars(double rating) {
    final fullCount = rating.floor();
    return Row(
      children: List.generate(
        5,
        (index) => Icon(
          index < fullCount ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 14,
        ),
      ),
    );
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

  Widget _buildStationSelectionWidget(String ownerId) {
    return StationSelectorWidget(
      ownerId: ownerId,
      selectedStationId: _selectedStationId,
      selectedFuelType: _selectedFuelType,
      onStationChanged: (stationId) {
        setState(() {
          _selectedStationId = stationId;
          if (stationId != null && _selectedFuelType != null) {
            _loadStationAnalytics(stationId, _selectedFuelType!);
          } else {
            _selectedStationAnalytics = null;
          }
        });
      },
      onFuelTypeChanged: (fuelType) {
        setState(() {
          _selectedFuelType = fuelType;
          if (_selectedStationId != null && fuelType != null) {
            _loadStationAnalytics(_selectedStationId!, fuelType);
          } else {
            _selectedStationAnalytics = null;
          }
        });
      },
    );
  }

  Widget _buildMarketTrendsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              const CircleAvatar(
                radius: 40,
                backgroundColor: Colors.green,
                child: Icon(
                  Icons.trending_up,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Market Trends',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Regional Price Analysis',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        _buildSectionHeader('Market Analysis'),

        if (_selectedTabIndex == 1) // Only show in market trends tab
          MarketTrendsChartWidget(
            analyticsData: _analyticsData,
            height: 300,
          ),

        const SizedBox(height: 16),

        // Time Period Selector
        _buildTimePeriodSelector(),

        const SizedBox(height: 16),

        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_analyticsData.isEmpty)
          const Center(child: Text('No market data available'))
        else
          _buildMarketOverview(),
      ],
    );
  }



  Widget _buildTimePeriodSelector() {
    return DropdownButtonFormField<String>(
      value: _selectedTimePeriod,
      decoration: const InputDecoration(
        labelText: 'Time Period',
        border: OutlineInputBorder(),
      ),
      items: _timePeriods.map((period) {
        return DropdownMenuItem(
          value: period,
          child: Text(period),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedTimePeriod = value!;
        });
        _loadAnalyticsData();
      },
    );
  }

  Widget _buildFuelTypeFilter() {
    return DropdownButtonFormField<String>(
      value: _selectedFuelType,
      decoration: const InputDecoration(
        labelText: 'Fuel Type',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('All Fuel Types'),
        ),
        ...['regular', 'midgrade', 'premium', 'diesel'].map((type) {
          return DropdownMenuItem(
            value: type,
            child: Text(type.toUpperCase()),
          );
        }).toList(),
      ],
      onChanged: (value) {
        setState(() {
          _selectedFuelType = value;
        });
        _loadAnalyticsData();
      },
    );
  }

  Widget _buildMarketOverview() {
    if (_analyticsData.isEmpty) return const SizedBox();

    final avgPrice = _analyticsData.fold<double>(0.0, 
      (sum, data) => sum + data.currentPrice) / _analyticsData.length;
    
    final increasing = _analyticsData.where((d) => d.isPriceIncreasing).length;
    final decreasing = _analyticsData.length - increasing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Market Overview',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMarketStat('Avg Price', '\$${avgPrice.toStringAsFixed(2)}'),
                _buildMarketStat('Stations', _analyticsData.length.toString()),
                _buildMarketStat('↑ Trends', '$increasing'),
                _buildMarketStat('↓ Trends', '$decreasing'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }
}
