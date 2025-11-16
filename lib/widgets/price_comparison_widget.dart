import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';
import 'package:intl/intl.dart';

class PriceComparisonWidget extends StatelessWidget {
  final List<AnalyticsData> analyticsList;
  final String fuelType;

  const PriceComparisonWidget({
    Key? key,
    required this.analyticsList,
    required this.fuelType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (analyticsList.isEmpty) {
      return const Center(child: Text('No data available for comparison'));
    }

    // Sort by current price
    final sorted = List<AnalyticsData>.from(analyticsList)
      ..sort((a, b) => a.currentPrice.compareTo(b.currentPrice));

    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Price Comparison - ${fuelType.toUpperCase()}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _getMaxPrice() * 1.1,
                  minY: _getMinPrice() * 0.95,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final station = sorted[groupIndex];
                        return BarTooltipItem(
                          '${station.stationName}\n₱${station.currentPrice.toStringAsFixed(2)}',
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
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < sorted.length) {
                            final station = sorted[value.toInt()];
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(
                                station.stationName.length > 10
                                    ? '${station.stationName.substring(0, 10)}...'
                                    : station.stationName,
                                style: const TextStyle(fontSize: 9),
                                textAlign: TextAlign.center,
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
                  barGroups: sorted.asMap().entries.map((entry) {
                    final index = entry.key;
                    final station = entry.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: station.currentPrice,
                          color: _getPriceColor(station.currentPrice),
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
            _buildStationList(sorted),
          ],
        ),
      ),
    );
  }

  Widget _buildStationList(List<AnalyticsData> sorted) {
    final cheapest = sorted.first;
    final mostExpensive = sorted.last;
    final average = sorted.fold<double>(0.0, (sum, s) => sum + s.currentPrice) / sorted.length;

    return Column(
      children: [
        _buildComparisonCard('Cheapest', cheapest, Colors.green),
        const SizedBox(height: 8),
        _buildComparisonCard('Average', null, Colors.orange, averagePrice: average),
        const SizedBox(height: 8),
        _buildComparisonCard('Most Expensive', mostExpensive, Colors.red),
      ],
    );
  }

  Widget _buildComparisonCard(String label, AnalyticsData? station, Color color, {double? averagePrice}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          Text(
            station != null
                ? '${station.stationName}: ₱${station.currentPrice.toStringAsFixed(2)}'
                : '₱${averagePrice!.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  double _getMaxPrice() {
    if (analyticsList.isEmpty) return 100;
    return analyticsList.map((a) => a.currentPrice).reduce((a, b) => a > b ? a : b);
  }

  double _getMinPrice() {
    if (analyticsList.isEmpty) return 0;
    return analyticsList.map((a) => a.currentPrice).reduce((a, b) => a < b ? a : b);
  }

  Color _getPriceColor(double price) {
    final min = _getMinPrice();
    final max = _getMaxPrice();
    final range = max - min;
    if (range == 0) return Colors.blue;

    final ratio = (price - min) / range;
    if (ratio < 0.33) return Colors.green;
    if (ratio < 0.66) return Colors.orange;
    return Colors.red;
  }
}

