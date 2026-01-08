import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';
import 'package:fuelgo/services/analytics_service.dart';
import 'package:fuelgo/services/auth_service.dart';
import 'package:fuelgo/services/firestore_service.dart';
import 'package:fuelgo/services/user_interaction_service.dart';
import 'package:fuelgo/services/user_preferences_service.dart';
import 'package:fuelgo/widgets/all_stations_analytics_widgets.dart';
import 'package:fuelgo/widgets/analytics_summary_widget.dart';
import 'package:fuelgo/widgets/enhanced_price_chart_widget.dart';
import 'package:fuelgo/widgets/gas_station_analytics_tile.dart';
import 'package:fuelgo/widgets/price_comparison_widget.dart';
import 'package:fuelgo/widgets/price_prediction_widget.dart';

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
  bool _isOwner = false;

  // Ratings data structure: stationId => { userId: { name, rating, comment } }
  Map<String, Map<String, Map<String, dynamic>>> _ratings = {};
  StreamSubscription<QuerySnapshot>? _ratingsSubscription;

  @override
  void initState() {
    super.initState();
    _selectedFuelType =
        null; // Initialize to 'regular' to load analytics immediately
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

          // If user is an owner, default to Market Trends tab (Wait, no, I changed this to Analytics tab)
          if (userRole == 'owner') {
            setState(() {
              _isOwner = true;
              _selectedTabIndex = 0; // My Analytics tab
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
    _ratingsSubscription = FirebaseFirestore.instance
        .collection('station_ratings')
        .snapshots()
        .listen((snapshot) {
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
          'rating': (data['rating'] is num)
              ? (data['rating'] as num).toDouble()
              : 0.0,
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
        if (_selectedTabIndex == 0) {
          // Owner analytics
          analytics = await AnalyticsService.getOwnerAnalytics(
            ownerId: user.uid,
            fuelType: _selectedFuelType,
            daysBack: daysBack,
          );
        } else {
          // Market trends
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
      if (e.toString().contains('PERMISSION_DENIED') ||
          e.toString().contains('Missing or insufficient permissions')) {
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

        // Track analytics view
        UserInteractionService.trackAnalyticsView(
          stationId: stationId,
          fuelType: fuelType,
        );

        // Track price view
        if (analytics.currentPrice > 0) {
          UserInteractionService.trackPriceView(
            stationId: stationId,
            stationName: stationName,
            fuelType: fuelType ?? 'all',
            price: analytics.currentPrice,
          );
        }
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
      builder: (context, _) {
        if (_isOwner) {
          // For owners, show only My Analytics (their own stations)
          return Scaffold(
            appBar: AppBar(
              title: const Text('Analytics'),
            ),
            body: _buildAnalyticsTab(),
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
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _loadAnalyticsData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Modern Header with Gradient
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.primaryColor,
                  theme.primaryColor.withOpacity(0.7)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: theme.primaryColor.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.analytics_outlined,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Analytics',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Track your stations performance',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Chip-Style Time Period Selector at Top
          _buildChipTimePeriodSelector(),

          const SizedBox(height: 24),

          // Analytics Summary Section
          AnalyticsSummaryWidget(
            analyticsData: _analyticsData,
            isLoading: _isLoading,
          ),

          const SizedBox(height: 24),

          // Price Analytics Section
          if (_selectedStationAnalytics != null) ...[
            _buildSectionCard(
              title: 'Price Analytics',
              icon: Icons.show_chart,
              iconColor: Colors.blue,
              child: EnhancedPriceChartWidget(
                analyticsData: _selectedStationAnalytics!,
                chartHeight: 350,
                showTitle: true,
              ),
            ),
            const SizedBox(height: 24),

            // Price Prediction Section
            _buildSectionCard(
              title: 'Price Prediction',
              icon: Icons.trending_up,
              iconColor: Colors.orange,
              child: PricePredictionWidget(
                analyticsData: _selectedStationAnalytics!,
                predictionDays: 7,
              ),
            ),
          ] else if (_isLoadingStationAnalytics)
            Container(
              padding: const EdgeInsets.all(32),
              child: const Center(child: CircularProgressIndicator()),
            )
          else
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.grey[50]!, Colors.grey[100]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[300]!, width: 1),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(Icons.local_gas_station,
                          size: 48, color: theme.primaryColor),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select a gas station',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose a station below to view detailed price history',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Price Comparison Section (if multiple stations selected)
          if (_analyticsData.length > 1 && _selectedFuelType != null) ...[
            Builder(
              builder: (context) {
                final comparisonList = _analyticsData
                    .where((a) =>
                        a.fuelType.toLowerCase() ==
                        _selectedFuelType!.toLowerCase())
                    .toList();

                // Track price comparison interaction
                if (comparisonList.length > 1) {
                  final stationIds =
                      comparisonList.map((a) => a.stationId).toList();
                  UserInteractionService.trackPriceComparison(
                    stationIds: stationIds,
                    fuelType: _selectedFuelType!,
                  );
                }

                return PriceComparisonWidget(
                  analyticsList: comparisonList,
                  fuelType: _selectedFuelType!,
                );
              },
            ),
            const SizedBox(height: 24),
          ],

          // Gas Station Selection
          _buildStationListWidget(),

          const SizedBox(height: 16),

          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_analyticsData.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildStationListWidget() {
    Map<String, double> _normalizePricesMap(Map<String, dynamic> prices) {
      final Map<String, double> normalized = {};
      prices.forEach((key, value) {
        final normalizedKey = key.toLowerCase();
        final price = (value as num).toDouble();
        if (!normalized.containsKey(normalizedKey) ||
            price < normalized[normalizedKey]!) {
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

        // Filter stations based on role if necessary
        final List<Map<String, dynamic>> visibleStations;
        if (_isOwner) {
          final user = AuthService().currentUser;
          visibleStations =
              allStations.where((s) => s['ownerId'] == user?.uid).toList();
        } else {
          visibleStations = allStations;
        }

        final filteredStations = _searchQuery.isEmpty
            ? visibleStations
            : visibleStations.where((station) {
                final name = (station['name'] ?? '').toLowerCase();
                final brand = (station['brand'] ?? '').toLowerCase();
                final query = _searchQuery.toLowerCase();
                return name.contains(query) || brand.contains(query);
              }).toList();

        if (allStations.isEmpty) {
          return const Center(child: Text('No gas stations found'));
        }

        // Collect all normalized fuel types from all stations for chip selector
        final Set<String> allFuelTypes = {};
        for (final station in filteredStations) {
          final prices = station['prices'] as Map<String, dynamic>? ?? {};
          final normalizedPrices = _normalizePricesMap(prices);
          allFuelTypes.addAll(normalizedPrices.keys);
        }
        final sortedFuelTypes = allFuelTypes.toList()..sort();

        final theme = Theme.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Explore Stations',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search gas stations...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),

            // Modern Chip-based Fuel Type Selection
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All Fuels'),
                      selected: _selectedFuelType == null,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedFuelType = null;
                            if (_selectedStationId != null) {
                              // Start with fresh analytics if changing context, usually keep station but clear fuel context or reloading analytics
                              // The existing logic passed _selectedFuelType which becomes null here
                              _loadStationAnalytics(_selectedStationId!, null);
                            } else {
                              _selectedStationAnalytics = null;
                            }
                          });
                        }
                      },
                      selectedColor: theme.primaryColor,
                      labelStyle: TextStyle(
                        color: _selectedFuelType == null
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: Colors.grey[200],
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      showCheckmark: false,
                    ),
                  ),
                  ...sortedFuelTypes.map((type) {
                    final isSelected = _selectedFuelType == type;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(type.toUpperCase()),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedFuelType = type;
                              if (_selectedStationId != null) {
                                _loadStationAnalytics(
                                    _selectedStationId!, type);
                              } else {
                                // Keep current station selection if any, just reload logic handles it?
                                // If no station selected, analytics is null.
                              }
                            });
                          }
                        },
                        selectedColor: theme.primaryColor,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: Colors.grey[200],
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        showCheckmark: false,
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),

            // Station List with new Tile Widget
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredStations.length,
              itemBuilder: (context, index) {
                final station = filteredStations[index];
                final stationId = station['id']?.toString();
                final isSelected = _selectedStationId == stationId;

                final rating =
                    _calculateAverageRating(_ratings[stationId ?? '']);

                return GasStationAnalyticsTile(
                  station: station,
                  isSelected: isSelected,
                  selectedFuelType: _selectedFuelType,
                  rating: rating,
                  prefsService: _prefsService,
                  onTap: (selectedId) {
                    // Track interaction
                    UserInteractionService.trackStationClick(
                      stationId: selectedId,
                      stationName: station['name'] ?? 'Unknown',
                    );

                    setState(() {
                      _selectedStationId = selectedId;
                      _loadStationAnalytics(selectedId, _selectedFuelType);
                    });
                  },
                );
              },
            ),
          ],
        );
      },
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

  Widget _buildMarketTrendsTab() {
    return AllStationsAnalyticsWidget(
      selectedTimePeriod: _selectedTimePeriod,
      selectedFuelType: _selectedFuelType,
      // Pass header and chip selector as optional parameters if the widget supports it,
      // otherwise we'll need to modify AllStationsAnalyticsWidget to accept custom headers
    );
  }

  Widget _buildChipTimePeriodSelector() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.access_time, size: 20, color: theme.primaryColor),
            const SizedBox(width: 8),
            const Text(
              'Time Period',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: _timePeriods.map((period) {
            final isSelected = _selectedTimePeriod == period;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilterChip(
                label: Text(period),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedTimePeriod = period;
                  });
                  _loadAnalyticsData();
                },
                backgroundColor: Colors.grey[100],
                selectedColor: theme.primaryColor.withOpacity(0.2),
                checkmarkColor: theme.primaryColor,
                labelStyle: TextStyle(
                  color: isSelected ? theme.primaryColor : Colors.grey[700],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? theme.primaryColor : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                elevation: isSelected ? 2 : 0,
              ),
            );
          }).toList(),
        ),
      ],
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

    final avgPrice = _analyticsData.fold<double>(
            0.0, (sum, data) => sum + data.currentPrice) /
        _analyticsData.length;

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
                _buildMarketStat(
                    'Avg Price', '\$${avgPrice.toStringAsFixed(2)}'),
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

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
