import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';
import 'package:intl/intl.dart';

class EnhancedMarketTrendsWidget extends StatefulWidget {
  final List<AnalyticsData> analyticsData;
  final double height;

  const EnhancedMarketTrendsWidget({
    Key? key,
    required this.analyticsData,
    this.height = 400,
  }) : super(key: key);

  @override
  State<EnhancedMarketTrendsWidget> createState() => _EnhancedMarketTrendsWidgetState();
}

class _EnhancedMarketTrendsWidgetState extends State<EnhancedMarketTrendsWidget> {
  String? _selectedFuelType;
  bool _expandedInsights = false;
  bool _showTimeSeries = true;
  int? _touchedBarIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.analyticsData.isEmpty) {
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
                Icon(Icons.trending_up, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No data available for market trends',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final fuelTypeData = _aggregateByFuelType();
    final timeSeriesData = _aggregateByTime();
    final filteredData = _selectedFuelType != null
        ? widget.analyticsData.where((d) => d.fuelType.toLowerCase() == _selectedFuelType!.toLowerCase()).toList()
        : widget.analyticsData;

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
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.trending_up, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Market Trends Analysis',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(_showTimeSeries ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() {
                      _showTimeSeries = !_showTimeSeries;
                    });
                  },
                  tooltip: _showTimeSeries ? 'Hide time series' : 'Show time series',
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Fuel Type Filter
            _buildFuelTypeFilter(fuelTypeData.keys.toList()),
            const SizedBox(height: 16),
            
            // Market Overview Stats
            _buildMarketOverview(fuelTypeData, filteredData),
            const SizedBox(height: 24),
            
            // Fuel Type Comparison Chart
            SizedBox(
              height: widget.height,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildFuelTypeChart(fuelTypeData),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTrendsSummary(fuelTypeData),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Insights Section
            _buildInsightsSection(fuelTypeData, filteredData),
            
            const SizedBox(height: 24),
            
            // Time Series Chart with toggle
            if (_showTimeSeries && timeSeriesData.isNotEmpty) ...[
              SizedBox(
                height: 300,
                child: _buildTimeSeriesChart(timeSeriesData),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFuelTypeFilter(List<String> fuelTypes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          const Text(
            'Filter:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', null),
                  const SizedBox(width: 8),
                  ...fuelTypes.map((type) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildFilterChip(type.toUpperCase(), type),
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value) {
    final isSelected = _selectedFuelType == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFuelType = selected ? value : null;
        });
      },
      backgroundColor: Colors.white,
      selectedColor: Colors.green.withOpacity(0.2),
      checkmarkColor: Colors.green,
      labelStyle: TextStyle(
        color: isSelected ? Colors.green : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildMarketOverview(Map<String, Map<String, dynamic>> fuelTypeData, List<AnalyticsData> filteredData) {
    final totalStations = filteredData.length;
    final avgPrice = filteredData.isEmpty 
        ? 0.0 
        : filteredData.fold<double>(0.0, (sum, data) => sum + data.currentPrice) / filteredData.length;
    final increasing = filteredData.where((d) => d.isPriceIncreasing).length;
    final decreasing = filteredData.length - increasing;
    final priceChange = filteredData.isEmpty 
        ? 0.0 
        : filteredData.fold<double>(0.0, (sum, data) => sum + (data.priceChange ?? 0.0)) / filteredData.length;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Stations',
            totalStations.toString(),
            Colors.blue,
            Icons.local_gas_station,
            subtitle: '${fuelTypeData.length} fuel types',
          ),
        ),
        Expanded(
          child: _buildStatCard(
            'Avg Price',
            '₱${avgPrice.toStringAsFixed(2)}',
            Colors.orange,
            Icons.trending_up,
            subtitle: priceChange >= 0 ? '+₱${priceChange.toStringAsFixed(2)}' : '₱${priceChange.toStringAsFixed(2)}',
          ),
        ),
        Expanded(
          child: _buildStatCard(
            '↑ Increasing',
            increasing.toString(),
            Colors.red,
            Icons.arrow_upward,
            subtitle: '${filteredData.isEmpty ? 0 : ((increasing / filteredData.length) * 100).toStringAsFixed(0)}%',
          ),
        ),
        Expanded(
          child: _buildStatCard(
            '↓ Decreasing',
            decreasing.toString(),
            Colors.green,
            Icons.arrow_downward,
            subtitle: '${filteredData.isEmpty ? 0 : ((decreasing / filteredData.length) * 100).toStringAsFixed(0)}%',
          ),
        ),
      ],
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
              fontSize: 18,
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

  Widget _buildFuelTypeChart(Map<String, Map<String, dynamic>> fuelTypeData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fuel Type Price Comparison',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: _getMaxY(fuelTypeData),
              barTouchData: BarTouchData(
                enabled: true,
                touchCallback: (FlTouchEvent event, barTouchResponse) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        barTouchResponse == null ||
                        barTouchResponse.spot == null) {
                      _touchedBarIndex = null;
                      return;
                    }
                    _touchedBarIndex = barTouchResponse.spot!.touchedBarGroupIndex;
                  });
                },
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final fuelType = fuelTypeData.keys.elementAt(groupIndex);
                    final data = fuelTypeData[fuelType]!;
                    final avg = data['avg'] as double;
                    final min = data['min'] as double;
                    final max = data['max'] as double;
                    final count = data['count'] as int;
                    return BarTooltipItem(
                      '${fuelType.toUpperCase()}\n'
                      'Avg: ₱${avg.toStringAsFixed(2)}\n'
                      'Min: ₱${min.toStringAsFixed(2)}\n'
                      'Max: ₱${max.toStringAsFixed(2)}\n'
                      'Stations: $count',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
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
                      if (value.toInt() < fuelTypeData.length) {
                        final fuelType = fuelTypeData.keys.elementAt(value.toInt());
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            fuelType.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
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
                    reservedSize: 45,
                    getTitlesWidget: (value, meta) {
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text(
                          '₱${value.toStringAsFixed(1)}',
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
              ),
              borderData: FlBorderData(show: true),
              barGroups: _buildBarGroups(fuelTypeData, _touchedBarIndex),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendsSummary(Map<String, Map<String, dynamic>> fuelTypeData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Price Summary',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: fuelTypeData.length,
            itemBuilder: (context, index) {
              final entry = fuelTypeData.entries.elementAt(index);
              final fuelType = entry.key;
              final data = entry.value;
              final avg = data['avg'] as double;
              final count = data['count'] as int;
              final min = data['min'] as double;
              final max = data['max'] as double;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getFuelTypeColor(fuelType).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getFuelTypeColor(fuelType).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _getFuelTypeColor(fuelType),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          fuelType.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildSummaryRow('Average', '₱${avg.toStringAsFixed(2)}'),
                    _buildSummaryRow('Min', '₱${min.toStringAsFixed(2)}'),
                    _buildSummaryRow('Max', '₱${max.toStringAsFixed(2)}'),
                    _buildSummaryRow('Stations', count.toString()),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
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
      ),
    );
  }

  Widget _buildTimeSeriesChart(Map<DateTime, Map<String, double>> timeSeriesData) {
    final sortedDates = timeSeriesData.keys.toList()..sort();
    final colors = [Colors.blue, Colors.orange, Colors.purple, Colors.grey];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Price Trends Over Time',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LineChart(
            LineChartData(
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
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    return touchedSpots.map((LineBarSpot touchedSpot) {
                      final fuelType = timeSeriesData[sortedDates[touchedSpot.x.toInt()]]?.keys.first ?? '';
                      return LineTooltipItem(
                        '${fuelType.toUpperCase()}\n₱${touchedSpot.y.toStringAsFixed(2)}',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    }).toList();
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: sortedDates.length > 10 ? sortedDates.length / 10 : 1,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() < sortedDates.length) {
                        final date = sortedDates[value.toInt()];
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Text(
                            DateFormat('MM/dd').format(date),
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
                    reservedSize: 45,
                    getTitlesWidget: (value, meta) {
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text(
                          '₱${value.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: true),
              lineBarsData: _buildTimeSeriesLines(sortedDates, timeSeriesData, colors),
            ),
          ),
        ),
      ],
    );
  }

  List<LineChartBarData> _buildTimeSeriesLines(
    List<DateTime> dates,
    Map<DateTime, Map<String, double>> timeSeriesData,
    List<Color> colors,
  ) {
    final fuelTypes = <String>{};
    for (final data in timeSeriesData.values) {
      fuelTypes.addAll(data.keys);
    }

    return fuelTypes.toList().asMap().entries.map((entry) {
      final index = entry.key;
      final fuelType = entry.value;
      final spots = dates.asMap().entries.map((dateEntry) {
        final date = dateEntry.value;
        final price = timeSeriesData[date]?[fuelType] ?? 0.0;
        return FlSpot(dateEntry.key.toDouble(), price);
      }).toList();

      return LineChartBarData(
        spots: spots,
        isCurved: true,
        color: colors[index % colors.length],
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: colors[index % colors.length].withOpacity(0.1),
        ),
      );
    }).toList();
  }

  Map<String, Map<String, dynamic>> _aggregateByFuelType() {
    final fuelTypeMap = <String, Map<String, dynamic>>{};

    for (final data in widget.analyticsData) {
      final fuelType = data.fuelType.toLowerCase();
      if (!fuelTypeMap.containsKey(fuelType)) {
        fuelTypeMap[fuelType] = {
          'prices': <double>[],
          'count': 0,
        };
      }

      fuelTypeMap[fuelType]!['prices'].add(data.currentPrice);
      fuelTypeMap[fuelType]!['count'] = fuelTypeMap[fuelType]!['count'] + 1;
    }

    // Calculate averages, min, max
    for (final fuelType in fuelTypeMap.keys) {
      final prices = fuelTypeMap[fuelType]!['prices'] as List<double>;
      final avg = prices.reduce((a, b) => a + b) / prices.length;
      final min = prices.reduce((a, b) => a < b ? a : b);
      final max = prices.reduce((a, b) => a > b ? a : b);
      fuelTypeMap[fuelType]!['avg'] = avg;
      fuelTypeMap[fuelType]!['min'] = min;
      fuelTypeMap[fuelType]!['max'] = max;
    }

    return fuelTypeMap;
  }

  Map<DateTime, Map<String, double>> _aggregateByTime() {
    final timeMap = <DateTime, Map<String, double>>{};

    for (final data in widget.analyticsData) {
      for (final point in data.pricePoints) {
        final date = DateTime(
          point.timestamp.year,
          point.timestamp.month,
          point.timestamp.day,
        );
        
        if (!timeMap.containsKey(date)) {
          timeMap[date] = {};
        }
        
        final fuelType = data.fuelType.toLowerCase();
        if (!timeMap[date]!.containsKey(fuelType)) {
          timeMap[date]![fuelType] = point.price;
        } else {
          // Average if multiple prices for same date
          timeMap[date]![fuelType] = (timeMap[date]![fuelType]! + point.price) / 2;
        }
      }
    }

    return timeMap;
  }

  List<BarChartGroupData> _buildBarGroups(Map<String, Map<String, dynamic>> fuelTypeData, int? touchedIndex) {
    final groups = <BarChartGroupData>[];
    var index = 0;

    for (final fuelType in fuelTypeData.keys) {
      final data = fuelTypeData[fuelType]!;
      final avgPrice = data['avg'] as double;
      final isTouched = touchedIndex == index;

      groups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: avgPrice,
              color: isTouched 
                  ? _getFuelTypeColor(fuelType).withOpacity(0.8)
                  : _getFuelTypeColor(fuelType),
              width: isTouched ? 30 : 20,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
      index++;
    }

    return groups;
  }

  Widget _buildInsightsSection(Map<String, Map<String, dynamic>> fuelTypeData, List<AnalyticsData> filteredData) {
    if (fuelTypeData.isEmpty || filteredData.isEmpty) return const SizedBox();

    // Find cheapest and most expensive fuel types
    final sortedByPrice = fuelTypeData.entries.toList()
      ..sort((a, b) => (a.value['avg'] as double).compareTo(b.value['avg'] as double));
    
    final cheapest = sortedByPrice.first;
    final mostExpensive = sortedByPrice.last;
    
    // Calculate price spread
    final priceSpread = (mostExpensive.value['avg'] as double) - (cheapest.value['avg'] as double);
    final spreadPercentage = ((priceSpread / cheapest.value['avg'] as double) * 100);

    return InkWell(
      onTap: () {
        setState(() {
          _expandedInsights = !_expandedInsights;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.withOpacity(0.1), Colors.green.withOpacity(0.1)],
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb, color: Colors.amber),
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
                Icon(_expandedInsights ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            if (_expandedInsights) ...[
              const SizedBox(height: 16),
              _buildInsightRow(
                Icons.local_gas_station,
                'Cheapest Fuel Type',
                '${cheapest.key.toUpperCase()} - ₱${cheapest.value['avg'].toStringAsFixed(2)}',
                Colors.green,
              ),
              const SizedBox(height: 8),
              _buildInsightRow(
                Icons.trending_up,
                'Most Expensive',
                '${mostExpensive.key.toUpperCase()} - ₱${mostExpensive.value['avg'].toStringAsFixed(2)}',
                Colors.red,
              ),
              const SizedBox(height: 8),
              _buildInsightRow(
                Icons.compare_arrows,
                'Price Spread',
                '₱${priceSpread.toStringAsFixed(2)} (${spreadPercentage.toStringAsFixed(1)}%)',
                Colors.orange,
              ),
              const SizedBox(height: 8),
              _buildInsightRow(
                Icons.analytics,
                'Total Stations',
                '${filteredData.length} stations tracked',
                Colors.blue,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInsightRow(IconData icon, String label, String value, Color color) {
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
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  double _getMaxY(Map<String, Map<String, dynamic>> fuelTypeData) {
    if (fuelTypeData.isEmpty) return 100;

    var maxPrice = 0.0;
    for (final data in fuelTypeData.values) {
      final avg = data['avg'] as double;
      if (avg > maxPrice) maxPrice = avg;
    }

    return maxPrice * 1.2;
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

