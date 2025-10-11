import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';

class MarketTrendsChartWidget extends StatelessWidget {
  final List<AnalyticsData> analyticsData;
  final double height;

  const MarketTrendsChartWidget({
    Key? key,
    required this.analyticsData,
    this.height = 300,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (analyticsData.isEmpty) {
      return const Center(child: Text('No data available for market trends'));
    }

    final fuelTypeData = _aggregateByFuelType();

    return Card(
      margin: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fuel Type Price Comparison',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: Colors.blueGrey,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final fuelType = fuelTypeData.keys.elementAt(groupIndex);
                        final data = fuelTypeData[fuelType]!;
                        return BarTooltipItem(
                          '$fuelType\nAvg: \$${data['avg']!.toStringAsFixed(2)}\nCount: ${data['count']}',
                          const TextStyle(color: Colors.white),
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
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              '\$${value.toStringAsFixed(1)}',
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
                    horizontalInterval: 0.5,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _buildBarGroups(fuelTypeData),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildLegend(context, fuelTypeData),
          ],
        ),
      ),
    );
  }

  Map<String, Map<String, dynamic>> _aggregateByFuelType() {
    final fuelTypeMap = <String, Map<String, dynamic>>{};

    for (final data in analyticsData) {
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

    // Calculate averages
    for (final fuelType in fuelTypeMap.keys) {
      final prices = fuelTypeMap[fuelType]!['prices'] as List<double>;
      final avg = prices.reduce((a, b) => a + b) / prices.length;
      fuelTypeMap[fuelType]!['avg'] = avg;
    }

    return fuelTypeMap;
  }

  List<BarChartGroupData> _buildBarGroups(Map<String, Map<String, dynamic>> fuelTypeData) {
    final groups = <BarChartGroupData>[];
    var index = 0;

    for (final fuelType in fuelTypeData.keys) {
      final data = fuelTypeData[fuelType]!;
      final avgPrice = data['avg'] as double;
      final count = data['count'] as int;

      groups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: avgPrice,
              color: _getFuelTypeColor(fuelType),
              width: 20,
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

  double _getMaxY(Map<String, Map<String, dynamic>> fuelTypeData) {
    if (fuelTypeData.isEmpty) return 10;

    var maxPrice = 0.0;
    for (final data in fuelTypeData.values) {
      final avg = data['avg'] as double;
      if (avg > maxPrice) maxPrice = avg;
    }

    return maxPrice * 1.2; // 20% buffer
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

  Widget _buildLegend(BuildContext context, Map<String, Map<String, dynamic>> fuelTypeData) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: fuelTypeData.entries.map((entry) {
        final fuelType = entry.key;
        final data = entry.value;
        final count = data['count'] as int;
        final avg = data['avg'] as double;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _getFuelTypeColor(fuelType),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${fuelType.toUpperCase()}: \$${avg.toStringAsFixed(2)} ($count stations)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      }).toList(),
    );
  }
}
