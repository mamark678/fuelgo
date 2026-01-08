import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';
import 'package:fuelgo/services/analytics_service.dart';
import 'package:fuelgo/services/firestore_service.dart';
import 'package:fuelgo/services/user_interaction_service.dart';

class AllStationsAnalyticsWidget extends StatefulWidget {
  final String selectedTimePeriod;
  final String? selectedFuelType;

  const AllStationsAnalyticsWidget({
    Key? key,
    required this.selectedTimePeriod,
    this.selectedFuelType,
  }) : super(key: key);

  @override
  State<AllStationsAnalyticsWidget> createState() =>
      _AllStationsAnalyticsWidgetState();
}

class _AllStationsAnalyticsWidgetState
    extends State<AllStationsAnalyticsWidget> {
  List<Map<String, dynamic>> _allStations = [];
  Map<String, AnalyticsData> _stationAnalytics = {};
  bool _isLoading = true;
  Set<String> _selectedStationIds = {};
  String _sortBy = 'price'; // price, name, trend, brand
  bool _sortAscending = true;
  String _searchQuery = '';
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    _loadAllStationsAnalytics();
  }

  @override
  void didUpdateWidget(AllStationsAnalyticsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTimePeriod != widget.selectedTimePeriod ||
        oldWidget.selectedFuelType != widget.selectedFuelType) {
      _loadAllStationsAnalytics();
    }
  }

  int _getDaysBack() {
    switch (widget.selectedTimePeriod) {
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

  Future<void> _loadAllStationsAnalytics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load all gas stations
      final stations = await FirestoreService.getAllGasStations();
      final daysBack = _getDaysBack();

      // Load analytics for each station
      final Map<String, AnalyticsData> analyticsMap = {};

      for (final station in stations) {
        final stationId = station['id']?.toString();
        final stationName = station['name']?.toString() ?? 'Unknown';

        if (stationId != null) {
          try {
            final analytics = await AnalyticsService.getStationAnalytics(
              stationId: stationId,
              stationName: stationName,
              fuelType: widget.selectedFuelType,
              daysBack: daysBack,
            );
            analyticsMap[stationId] = analytics;
          } catch (e) {
            print('Error loading analytics for station $stationId: $e');
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _allStations = stations;
        _stationAnalytics = analyticsMap;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading all stations analytics: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredAndSortedStations() {
    var filtered = _allStations.where((station) {
      if (_searchQuery.isEmpty) return true;

      final name = (station['name'] ?? '').toString().toLowerCase();
      final brand = (station['brand'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      return name.contains(query) || brand.contains(query);
    }).toList();

    // Sort stations
    filtered.sort((a, b) {
      final aId = a['id']?.toString() ?? '';
      final bId = b['id']?.toString() ?? '';
      final aAnalytics = _stationAnalytics[aId];
      final bAnalytics = _stationAnalytics[bId];

      int comparison = 0;

      switch (_sortBy) {
        case 'price':
          final aPrice = aAnalytics?.currentPrice ?? double.infinity;
          final bPrice = bAnalytics?.currentPrice ?? double.infinity;
          comparison = aPrice.compareTo(bPrice);
          break;
        case 'name':
          comparison = (a['name'] ?? '')
              .toString()
              .compareTo((b['name'] ?? '').toString());
          break;
        case 'brand':
          comparison = (a['brand'] ?? '')
              .toString()
              .compareTo((b['brand'] ?? '').toString());
          break;
        case 'trend':
          final aTrend = aAnalytics?.priceChangePercentage ?? 0;
          final bTrend = bAnalytics?.priceChangePercentage ?? 0;
          comparison = aTrend.compareTo(bTrend);
          break;
      }

      return _sortAscending ? comparison : -comparison;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final filteredStations = _getFilteredAndSortedStations();
    final selectedAnalytics = _selectedStationIds
        .map((id) => _stationAnalytics[id])
        .where((a) => a != null)
        .cast<AnalyticsData>()
        .toList();

    return RefreshIndicator(
      onRefresh: _loadAllStationsAnalytics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 16),

          // Top Statistics
          _buildTopStatistics(),
          const SizedBox(height: 16),

          // Filter and Sort Bar
          _buildFilterSortBar(),
          const SizedBox(height: 16),

          // Selected Stations Comparison
          if (_selectedStationIds.isNotEmpty) ...[
            _buildComparisonSection(selectedAnalytics),
            const SizedBox(height: 16),
          ],

          // Stations Grid/List
          if (filteredStations.isEmpty)
            _buildEmptyState()
          else if (_isGridView)
            _buildStationsGrid(filteredStations)
          else
            _buildStationsList(filteredStations),

          const SizedBox(height: 16),

          // Market Insights
          _buildMarketInsights(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.store, color: Colors.blue, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'All Gas Stations',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_allStations.length} stations • ${widget.selectedTimePeriod}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopStatistics() {
    if (_allStations.isEmpty) return const SizedBox();

    // Collect actual prices from station data
    final List<double> prices = [];

    for (final station in _allStations) {
      final stationPrices = station['prices'] as Map<String, dynamic>? ?? {};
      final normalizedPrices = <String, double>{};
      stationPrices.forEach((key, value) {
        normalizedPrices[key.toLowerCase()] = (value as num).toDouble();
      });

      final fuelType = widget.selectedFuelType?.toLowerCase();

      if (fuelType != null && normalizedPrices.containsKey(fuelType)) {
        // If a specific fuel type is selected, only use that fuel type's price
        final price = normalizedPrices[fuelType];
        if (price != null && price > 0) {
          prices.add(price);
        }
      } else if (fuelType == null) {
        // If no fuel type is selected, include ALL fuel prices from this station
        for (final price in normalizedPrices.values) {
          if (price > 0) {
            prices.add(price);
          }
        }
      }
    }

    if (prices.isEmpty) return const SizedBox();

    final avgPrice = prices.reduce((a, b) => a + b) / prices.length;
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final increasing =
        _stationAnalytics.values.where((a) => a.isPriceIncreasing).length;
    final decreasing = _stationAnalytics.length - increasing;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Market Overview',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Average',
                    '₱${avgPrice.toStringAsFixed(2)}',
                    Icons.show_chart,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Lowest',
                    '₱${minPrice.toStringAsFixed(2)}',
                    Icons.arrow_downward,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Highest',
                    '₱${maxPrice.toStringAsFixed(2)}',
                    Icons.arrow_upward,
                    Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Increasing',
                    '$increasing',
                    Icons.trending_up,
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Decreasing',
                    '$decreasing',
                    Icons.trending_down,
                    Colors.teal,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Stations',
                    '${_allStations.length}',
                    Icons.store,
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSortBar() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Search Bar
            TextField(
              decoration: InputDecoration(
                hintText: 'Search stations...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 12),
            // Sort and View Controls
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _sortBy,
                    decoration: InputDecoration(
                      labelText: 'Sort by',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'price', child: Text('Price')),
                      DropdownMenuItem(value: 'name', child: Text('Name')),
                      DropdownMenuItem(value: 'brand', child: Text('Brand')),
                      DropdownMenuItem(value: 'trend', child: Text('Trend')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _sortBy = value!;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(_sortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward),
                  onPressed: () {
                    setState(() {
                      _sortAscending = !_sortAscending;
                    });
                  },
                  tooltip: _sortAscending ? 'Ascending' : 'Descending',
                ),
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                  onPressed: () {
                    setState(() {
                      _isGridView = !_isGridView;
                    });
                  },
                  tooltip: _isGridView ? 'List View' : 'Grid View',
                ),
                if (_selectedStationIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_all),
                    onPressed: () {
                      setState(() {
                        _selectedStationIds.clear();
                      });
                    },
                    tooltip: 'Clear Selection',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonSection(List<AnalyticsData> selectedAnalytics) {
    if (selectedAnalytics.isEmpty) return const SizedBox();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows, color: Colors.purple),
                const SizedBox(width: 8),
                Text(
                  'Comparing ${selectedAnalytics.length} Stations',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Price Comparison Chart
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: selectedAnalytics
                          .map((a) => a.currentPrice)
                          .reduce((a, b) => a > b ? a : b) *
                      1.1,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final analytics = selectedAnalytics[groupIndex];
                        return BarTooltipItem(
                          '${analytics.stationName}\n₱${analytics.currentPrice.toStringAsFixed(2)}',
                          const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < selectedAnalytics.length) {
                            final name =
                                selectedAnalytics[value.toInt()].stationName;
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(
                                name.length > 10
                                    ? '${name.substring(0, 10)}...'
                                    : name,
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '₱${value.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: true),
                  barGroups: selectedAnalytics.asMap().entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value.currentPrice,
                          color: _getBrandColor(entry.value.stationName),
                          width: 20,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Price Difference
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: selectedAnalytics.map((analytics) {
                final minPrice = selectedAnalytics
                    .map((a) => a.currentPrice)
                    .reduce((a, b) => a < b ? a : b);
                final difference = analytics.currentPrice - minPrice;
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor:
                        difference == 0 ? Colors.green : Colors.orange,
                    child: Icon(
                      difference == 0 ? Icons.check : Icons.add,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  label: Text(
                    '${analytics.stationName}: ${difference == 0 ? 'Best' : '+₱${difference.toStringAsFixed(2)}'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationsList(List<Map<String, dynamic>> stations) {
    return Column(
      children:
          stations.map((station) => _buildStationCard(station, false)).toList(),
    );
  }

  Widget _buildStationsGrid(List<Map<String, dynamic>> stations) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: stations.length,
      itemBuilder: (context, index) => _buildStationCard(stations[index], true),
    );
  }

  Widget _buildStationCard(Map<String, dynamic> station, bool isCompact) {
    final stationId = station['id']?.toString() ?? '';
    final stationName = station['name']?.toString() ?? 'Unknown';
    final brand = station['brand']?.toString() ?? '';
    final analytics = _stationAnalytics[stationId];
    final isSelected = _selectedStationIds.contains(stationId);

    final prices = station['prices'] as Map<String, dynamic>? ?? {};
    final normalizedPrices = <String, double>{};
    prices.forEach((key, value) {
      normalizedPrices[key.toLowerCase()] = (value as num).toDouble();
    });

    final fuelType = widget.selectedFuelType?.toLowerCase();
    final price = fuelType != null && normalizedPrices.containsKey(fuelType)
        ? normalizedPrices[fuelType]
        : (normalizedPrices.values.isNotEmpty
            ? normalizedPrices.values.first
            : 0.0);

    return Card(
      elevation: isSelected ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.purple : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedStationIds.remove(stationId);
            } else {
              _selectedStationIds.add(stationId);
            }
          });

          // Track interaction
          UserInteractionService.trackStationClick(
            stationId: stationId,
            stationName: stationName,
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getBrandColor(brand).withOpacity(0.2),
                    child: Text(
                      brand.isNotEmpty ? brand[0].toUpperCase() : 'G',
                      style: TextStyle(
                        color: _getBrandColor(brand),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stationName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          brand,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Checkbox(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedStationIds.add(stationId);
                        } else {
                          _selectedStationIds.remove(stationId);
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₱${price?.toStringAsFixed(2) ?? 'N/A'}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Text(
                        '/L',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  if (analytics != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: analytics.isPriceIncreasing
                            ? Colors.red.withOpacity(0.1)
                            : Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            analytics.isPriceIncreasing
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 16,
                            color: analytics.isPriceIncreasing
                                ? Colors.red
                                : Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${analytics.priceChangePercentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: analytics.isPriceIncreasing
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (!isCompact && analytics != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildMiniStat(
                        'Avg', '₱${analytics.averagePrice.toStringAsFixed(2)}'),
                    _buildMiniStat(
                        'Min', '₱${analytics.minPrice.toStringAsFixed(2)}'),
                    _buildMiniStat(
                        'Max', '₱${analytics.maxPrice.toStringAsFixed(2)}'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No stations found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search filters',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketInsights() {
    if (_stationAnalytics.isEmpty) return const SizedBox();

    // Find best deals
    final stationsWithPrices = _stationAnalytics.entries
        .where((e) => e.value.currentPrice > 0)
        .toList()
      ..sort((a, b) => a.value.currentPrice.compareTo(b.value.currentPrice));

    if (stationsWithPrices.isEmpty) return const SizedBox();

    final cheapest = stationsWithPrices.first;
    final mostExpensive = stationsWithPrices.last;

    // Calculate brand averages
    final brandPrices = <String, List<double>>{};
    for (final station in _allStations) {
      final brand = station['brand']?.toString() ?? 'Unknown';
      final stationId = station['id']?.toString();
      final analytics = stationId != null ? _stationAnalytics[stationId] : null;
      if (analytics != null && analytics.currentPrice > 0) {
        brandPrices.putIfAbsent(brand, () => []).add(analytics.currentPrice);
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: Colors.amber),
                const SizedBox(width: 8),
                const Text(
                  'Market Insights',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInsightItem(
              Icons.star,
              'Best Deal',
              cheapest.value.stationName,
              '₱${cheapest.value.currentPrice.toStringAsFixed(2)}',
              Colors.green,
            ),
            const SizedBox(height: 8),
            _buildInsightItem(
              Icons.trending_up,
              'Most Expensive',
              mostExpensive.value.stationName,
              '₱${mostExpensive.value.currentPrice.toStringAsFixed(2)}',
              Colors.red,
            ),
            if (brandPrices.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Average Price by Brand',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...brandPrices.entries.map((entry) {
                final avg =
                    entry.value.reduce((a, b) => a + b) / entry.value.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getBrandColor(entry.key),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(entry.key),
                        ],
                      ),
                      Text(
                        '₱${avg.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInsightItem(
    IconData icon,
    String label,
    String stationName,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color,
            radius: 20,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  stationName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
      ),
    );
  }

  Color _getBrandColor(String brand) {
    // Map brands to colors for consistency
    final brandLower = brand.toLowerCase();
    if (brandLower.contains('shell')) return Colors.red;
    if (brandLower.contains('petron')) return Colors.blue;
    if (brandLower.contains('caltex')) return Colors.orange;
    if (brandLower.contains('total')) return Colors.red.shade700;
    if (brandLower.contains('seaoil')) return Colors.green;
    if (brandLower.contains('phoenix')) return Colors.orange.shade700;
    if (brandLower.contains('cleanfuel')) return Colors.teal;
    if (brandLower.contains('unioil')) return Colors.purple;

    // Default color based on hash for consistency
    final hash = brand.hashCode;
    final colors = [
      Colors.indigo,
      Colors.pink,
      Colors.cyan,
      Colors.amber,
      Colors.lime,
      Colors.deepOrange,
    ];
    return colors[hash.abs() % colors.length];
  }
}
