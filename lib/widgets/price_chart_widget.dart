import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';

class PriceChartWidget extends StatefulWidget {
  final AnalyticsData analyticsData;
  final double chartHeight;
  final bool showTitle;

  const PriceChartWidget({
    Key? key,
    required this.analyticsData,
    this.chartHeight = 200,
    this.showTitle = true,
  }) : super(key: key);

  @override
  _PriceChartWidgetState createState() => _PriceChartWidgetState();
}

class _PriceChartWidgetState extends State<PriceChartWidget> {
  String _selectedTimePeriod = '30D'; // Default time period

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showTitle)
              Text(
                '${widget.analyticsData.stationName} - ${widget.analyticsData.fuelType.toUpperCase()}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            if (widget.showTitle) const SizedBox(height: 8),
            // Time Period Selector
            DropdownButton<String>(
              value: _selectedTimePeriod,
              items: ['7D', '30D', '90D', '1Y'].map((String period) {
                return DropdownMenuItem<String>(
                  value: period,
                  child: Text(period),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedTimePeriod = newValue!;
                });
                // Fetch and update data based on the selected time period
                _fetchDataForTimePeriod(_selectedTimePeriod);
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: widget.chartHeight,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          if (widget.analyticsData.pricePoints.isNotEmpty &&
                              value.toInt() < widget.analyticsData.pricePoints.length) {
                            final point = widget.analyticsData.pricePoints[value.toInt()];
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(
                                _formatDate(point.timestamp),
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
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              '\$${value.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  minX: 0,
                  maxX: widget.analyticsData.pricePoints.length > 1
                      ? (widget.analyticsData.pricePoints.length - 1).toDouble()
                      : 1,
                  minY: _getMinY(),
                  maxY: _getMaxY(),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _getSpots(),
                      isCurved: true,
                      color: _getLineColor(),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildStatsRow(context),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _getSpots() {
    return widget.analyticsData.pricePoints.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.price);
    }).toList();
  }

  double _getMinY() {
    if (widget.analyticsData.pricePoints.isEmpty) return 0;
    final minPrice = widget.analyticsData.pricePoints
        .map((p) => p.price)
        .reduce((a, b) => a < b ? a : b);
    return (minPrice * 0.95); // 5% buffer below min
  }

  double _getMaxY() {
    if (widget.analyticsData.pricePoints.isEmpty) return 10;
    final maxPrice = widget.analyticsData.pricePoints
        .map((p) => p.price)
        .reduce((a, b) => a > b ? a : b);
    return (maxPrice * 1.05); // 5% buffer above max
  }

  Color _getLineColor() {
    if (widget.analyticsData.priceChange == 0) return Colors.blue;
    return widget.analyticsData.isPriceIncreasing ? Colors.red : Colors.green;
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}';
  }

  void _fetchDataForTimePeriod(String period) {
    // Logic to fetch data based on the selected time period
    // This will involve querying the analytics data for the specified duration
    // For now, we'll just update the state to trigger a rebuild
    setState(() {
      // This is a placeholder - actual data fetching should be implemented
    });
  }

  Widget _buildStatsRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(
          context,
          'Current',
          '\$${widget.analyticsData.currentPrice.toStringAsFixed(2)}',
          Colors.blue,
        ),
        _buildStatItem(
          context,
          'Avg',
          '\$${widget.analyticsData.averagePrice.toStringAsFixed(2)}',
          Colors.orange,
        ),
        _buildStatItem(
          context,
          'Change',
          '${widget.analyticsData.priceChange > 0 ? '+' : ''}${widget.analyticsData.priceChange.toStringAsFixed(2)}%',
          widget.analyticsData.isPriceIncreasing ? Colors.red : Colors.green,
        ),
      ],
    );
  }

  Widget _buildStatItem(
      BuildContext context, String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
