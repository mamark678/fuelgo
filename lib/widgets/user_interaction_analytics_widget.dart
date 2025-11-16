import 'package:flutter/material.dart';
import 'package:fuelgo/services/user_interaction_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fuelgo/services/firestore_service.dart';

class UserInteractionAnalyticsWidget extends StatefulWidget {
  const UserInteractionAnalyticsWidget({Key? key}) : super(key: key);

  @override
  State<UserInteractionAnalyticsWidget> createState() => _UserInteractionAnalyticsWidgetState();
}

class _UserInteractionAnalyticsWidgetState extends State<UserInteractionAnalyticsWidget> {
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;
  String _selectedTimePeriod = '30 days';
  final List<String> _timePeriods = ['7 days', '30 days', '90 days'];
  bool _expandedInsights = false;
  bool _expandedStations = false;
  Map<String, String>? _stationNames;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
    _loadStationNames();
  }

  Future<void> _loadStationNames() async {
    try {
      final stations = await FirestoreService.getAllGasStations();
      final names = <String, String>{};
      for (final station in stations) {
        final id = station['id']?.toString() ?? '';
        final name = station['name']?.toString() ?? 'Unknown';
        if (id.isNotEmpty) {
          names[id] = name;
        }
      }
      setState(() {
        _stationNames = names;
      });
    } catch (e) {
      print('Error loading station names: $e');
    }
  }

  int _getDaysBack() {
    switch (_selectedTimePeriod) {
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

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final daysBack = _getDaysBack();
      final analytics = await UserInteractionService.getUserInteractionAnalytics(daysBack: daysBack);
      setState(() {
        _analytics = analytics;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        margin: const EdgeInsets.all(8),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_analytics == null || _analytics!.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(8),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insights, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No interaction data available yet',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start exploring stations to see your activity',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final totalInteractions = _analytics!['totalInteractions'] ?? 0;
    final priceViews = _analytics!['priceViews'] ?? 0;
    final stationClicks = _analytics!['stationClicks'] ?? 0;
    final analyticsViews = _analytics!['analyticsViews'] ?? 0;
    final priceComparisons = _analytics!['priceComparisons'] ?? 0;
    final fuelTypeViews = _analytics!['fuelTypeViews'] as Map<String, dynamic>? ?? {};
    final stationViews = _analytics!['stationViews'] as Map<String, dynamic>? ?? {};
    final mostViewedFuelType = _analytics!['mostViewedFuelType'] as String?;
    final mostViewedStation = _analytics!['mostViewedStation'] as String?;

    return Card(
      margin: const EdgeInsets.all(8),
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
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.insights, color: Colors.purple, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Activity Analytics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Last $_selectedTimePeriod',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Filter by time period',
                  onSelected: (value) {
                    setState(() {
                      _selectedTimePeriod = value;
                    });
                    _loadAnalytics();
                  },
                  itemBuilder: (context) => _timePeriods.map((period) {
                    return PopupMenuItem(
                      value: period,
                      child: Row(
                        children: [
                          Icon(
                            _selectedTimePeriod == period ? Icons.check : null,
                            size: 20,
                            color: Colors.purple,
                          ),
                          const SizedBox(width: 8),
                          Text(period),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadAnalytics,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Summary Stats with better layout
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total Interactions',
                    totalInteractions.toString(),
                    Colors.blue,
                    Icons.touch_app,
                    subtitle: 'All activities',
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    'Price Views',
                    priceViews.toString(),
                    Colors.green,
                    Icons.visibility,
                    subtitle: '${totalInteractions > 0 ? ((priceViews / totalInteractions) * 100).toStringAsFixed(0) : 0}%',
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    'Station Clicks',
                    stationClicks.toString(),
                    Colors.orange,
                    Icons.location_on,
                    subtitle: 'Stations explored',
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    'Comparisons',
                    priceComparisons.toString(),
                    Colors.purple,
                    Icons.compare_arrows,
                    subtitle: 'Price comparisons',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Interaction Type Chart with better interactivity
            if (totalInteractions > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Interaction Distribution',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _expandedInsights = !_expandedInsights;
                      });
                    },
                    icon: Icon(_expandedInsights ? Icons.expand_less : Icons.expand_more),
                    label: Text(_expandedInsights ? 'Less' : 'More'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 250,
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: PieChart(
                        PieChartData(
                          sections: [
                            if (priceViews > 0)
                              PieChartSectionData(
                                value: priceViews.toDouble(),
                                title: '${((priceViews / totalInteractions) * 100).toStringAsFixed(0)}%\nViews',
                                color: Colors.green,
                                radius: 70,
                                showTitle: true,
                              ),
                            if (stationClicks > 0)
                              PieChartSectionData(
                                value: stationClicks.toDouble(),
                                title: '${((stationClicks / totalInteractions) * 100).toStringAsFixed(0)}%\nClicks',
                                color: Colors.orange,
                                radius: 70,
                                showTitle: true,
                              ),
                            if (analyticsViews > 0)
                              PieChartSectionData(
                                value: analyticsViews.toDouble(),
                                title: '${((analyticsViews / totalInteractions) * 100).toStringAsFixed(0)}%\nAnalytics',
                                color: Colors.purple,
                                radius: 70,
                                showTitle: true,
                              ),
                            if (priceComparisons > 0)
                              PieChartSectionData(
                                value: priceComparisons.toDouble(),
                                title: '${((priceComparisons / totalInteractions) * 100).toStringAsFixed(0)}%\nCompare',
                                color: Colors.blue,
                                radius: 70,
                                showTitle: true,
                              ),
                          ],
                          sectionsSpace: 3,
                          centerSpaceRadius: 50,
                          pieTouchData: PieTouchData(
                            touchCallback: (FlTouchEvent event, pieTouchResponse) {
                              if (!event.isInterestedForInteractions ||
                                  pieTouchResponse == null ||
                                  pieTouchResponse.touchedSection == null) {
                                return;
                              }
                              // Show tooltip or navigate on tap
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLegendItem('Price Views', Colors.green, priceViews),
                          const SizedBox(height: 8),
                          _buildLegendItem('Station Clicks', Colors.orange, stationClicks),
                          const SizedBox(height: 8),
                          _buildLegendItem('Analytics Views', Colors.purple, analyticsViews),
                          const SizedBox(height: 8),
                          _buildLegendItem('Comparisons', Colors.blue, priceComparisons),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_expandedInsights) ...[
                const SizedBox(height: 16),
                _buildInsightsSection(),
              ],
            ],
            
            // Fuel Type Views with better interactivity
            if (fuelTypeViews.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Fuel Type Preferences',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.local_gas_station, size: 16),
                    label: Text('${fuelTypeViews.length} types'),
                    backgroundColor: Colors.blue.withOpacity(0.1),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: fuelTypeViews.values.reduce((a, b) => (a is num ? a.toDouble() : (a as int).toDouble()) > (b is num ? b.toDouble() : (b as int).toDouble()) ? a : b).toDouble() * 1.2,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final fuelType = fuelTypeViews.keys.elementAt(groupIndex);
                          final count = fuelTypeViews[fuelType];
                          return BarTooltipItem(
                            '${fuelType.toUpperCase()}\n$count views',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                            if (value.toInt() < fuelTypeViews.length) {
                              final fuelType = fuelTypeViews.keys.elementAt(value.toInt());
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text(
                                  fuelType.toUpperCase(),
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
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
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(
                                value.toInt().toString(),
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: Colors.grey.withOpacity(0.2),
                          strokeWidth: 1,
                        );
                      },
                    ),
                    borderData: FlBorderData(show: true),
                    barGroups: fuelTypeViews.entries.toList().asMap().entries.map((entry) {
                      final fuelType = entry.value.key;
                      final count = entry.value.value;
                      return BarChartGroupData(
                        x: entry.key,
                        barRods: [
                          BarChartRodData(
                            toY: (count is num ? count.toDouble() : (count as int).toDouble()),
                            color: _getFuelTypeColor(fuelType),
                            width: 30,
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
            ],
            
            // Station Views Section
            if (stationViews.isNotEmpty) ...[
              const SizedBox(height: 24),
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedStations = !_expandedStations;
                  });
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Most Viewed Stations',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Icon(_expandedStations ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
              if (_expandedStations) ...[
                const SizedBox(height: 16),
                ...() {
                  final sortedStations = stationViews.entries.toList()
                    ..sort((a, b) {
                      final aVal = a.value is num ? a.value.toDouble() : (a.value as int).toDouble();
                      final bVal = b.value is num ? b.value.toDouble() : (b.value as int).toDouble();
                      return bVal.compareTo(aVal);
                    });
                  
                  return sortedStations.take(5).toList().asMap().entries.map((entry) {
                    final index = entry.key;
                    final stationEntry = entry.value;
                    final stationId = stationEntry.key;
                    final views = stationEntry.value;
                    final stationName = _stationNames?[stationId] ?? 'Unknown Station';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.local_gas_station, color: Colors.orange, size: 20),
                          ),
                          const SizedBox(width: 12),
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
                                ),
                                Text(
                                  '$views views',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: Text('#${index + 1}'),
                            backgroundColor: Colors.orange.withOpacity(0.1),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                }(),
              ],
            ],
            
            // Insights Section
            if (mostViewedFuelType != null || mostViewedStation != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.withOpacity(0.1), Colors.purple.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lightbulb, color: Colors.amber),
                        const SizedBox(width: 8),
                        const Text(
                          'Insights',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (mostViewedFuelType != null)
                      _buildInsightItem(
                        Icons.local_gas_station,
                        'Most Viewed Fuel Type',
                        mostViewedFuelType.toUpperCase(),
                        Colors.blue,
                      ),
                    if (mostViewedStation != null && _stationNames != null) ...[
                      const SizedBox(height: 8),
                      _buildInsightItem(
                        Icons.star,
                        'Favorite Station',
                        _stationNames![mostViewedStation] ?? 'Unknown',
                        Colors.orange,
                      ),
                    ],
                    if (totalInteractions > 0) ...[
                      const SizedBox(height: 8),
                      _buildInsightItem(
                        Icons.trending_up,
                        'Activity Level',
                        totalInteractions > 50 ? 'Very Active' : totalInteractions > 20 ? 'Active' : 'Getting Started',
                        Colors.green,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 9,
                color: color.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int value) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildInsightItem(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildInsightsSection() {
    final totalInteractions = _analytics!['totalInteractions'] ?? 0;
    final priceViews = _analytics!['priceViews'] ?? 0;
    final stationClicks = _analytics!['stationClicks'] ?? 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Activity Breakdown',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildActivityRow('Price Views', priceViews, totalInteractions, Colors.green),
          _buildActivityRow('Station Clicks', stationClicks, totalInteractions, Colors.orange),
          _buildActivityRow('Analytics Views', _analytics!['analyticsViews'] ?? 0, totalInteractions, Colors.purple),
          _buildActivityRow('Price Comparisons', _analytics!['priceComparisons'] ?? 0, totalInteractions, Colors.blue),
        ],
      ),
    );
  }

  Widget _buildActivityRow(String label, int value, int total, Color color) {
    final percentage = total > 0 ? (value / total) * 100 : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '$value (${percentage.toStringAsFixed(1)}%)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Color _getFuelTypeColor(String fuelType) {
    switch (fuelType.toLowerCase()) {
      case 'regular':
        return Colors.blue;
      case 'midgrade':
        return Colors.orange;
      case 'premium':
        return Colors.purple;
      case 'diesel':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }
}

