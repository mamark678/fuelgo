import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';
import 'package:intl/intl.dart';

class EnhancedPriceChartWidget extends StatefulWidget {
  final AnalyticsData analyticsData;
  final double chartHeight;
  final bool showTitle;
  final bool showComparison;
  final AnalyticsData? comparisonData;

  const EnhancedPriceChartWidget({
    Key? key,
    required this.analyticsData,
    this.chartHeight = 300,
    this.showTitle = true,
    this.showComparison = false,
    this.comparisonData,
  }) : super(key: key);

  @override
  State<EnhancedPriceChartWidget> createState() => _EnhancedPriceChartWidgetState();
}

class _EnhancedPriceChartWidgetState extends State<EnhancedPriceChartWidget> {
  bool _showDots = false;
  bool _showArea = true;
  String _chartType = 'line'; // 'line', 'bar', 'candlestick'
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.showTitle)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.analyticsData.stationName} - ${widget.analyticsData.fuelType.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Price History',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                // Chart type selector
                Row(
                  children: [
                    IconButton(
                      icon: Icon(_chartType == 'line' ? Icons.show_chart : Icons.show_chart_outlined),
                      onPressed: () => setState(() => _chartType = 'line'),
                      tooltip: 'Line Chart',
                      color: _chartType == 'line' ? Colors.blue : Colors.grey,
                    ),
                    IconButton(
                      icon: Icon(_chartType == 'bar' ? Icons.bar_chart : Icons.bar_chart_outlined),
                      onPressed: () => setState(() => _chartType = 'bar'),
                      tooltip: 'Bar Chart',
                      color: _chartType == 'bar' ? Colors.blue : Colors.grey,
                    ),
                    IconButton(
                      icon: Icon(_showDots ? Icons.circle : Icons.circle_outlined),
                      onPressed: () => setState(() => _showDots = !_showDots),
                      tooltip: 'Show Dots',
                    ),
                    IconButton(
                      icon: Icon(_showArea ? Icons.area_chart : Icons.area_chart_outlined),
                      onPressed: () => setState(() => _showArea = !_showArea),
                      tooltip: 'Show Area',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Stats cards
            _buildQuickStats(),
            const SizedBox(height: 16),
            
            // Chart
            SizedBox(
              height: widget.chartHeight,
              child: _chartType == 'line' ? _buildLineChart() : _buildBarChart(),
            ),
            
            // Legend and comparison toggle
            if (widget.showComparison && widget.comparisonData != null) ...[
              const SizedBox(height: 16),
              _buildComparisonLegend(),
            ],
            
            // Price change indicator
            const SizedBox(height: 8),
            _buildPriceChangeIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Current',
            '₱${widget.analyticsData.currentPrice.toStringAsFixed(2)}',
            Colors.blue,
            Icons.local_gas_station,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Average',
            '₱${widget.analyticsData.averagePrice.toStringAsFixed(2)}',
            Colors.orange,
            Icons.trending_up,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Min',
            '₱${widget.analyticsData.minPrice.toStringAsFixed(2)}',
            Colors.green,
            Icons.arrow_downward,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Max',
            '₱${widget.analyticsData.maxPrice.toStringAsFixed(2)}',
            Colors.red,
            Icons.arrow_upward,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
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
      ),
    );
  }

  Widget _buildLineChart() {
    final spots = widget.analyticsData.pricePoints.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.price);
    }).toList();

    final comparisonSpots = widget.showComparison && widget.comparisonData != null
        ? widget.comparisonData!.pricePoints.asMap().entries.map((entry) {
            return FlSpot(entry.key.toDouble(), entry.value.price);
          }).toList()
        : null;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _getPriceInterval(),
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.withOpacity(0.2),
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: _getXInterval(),
              getTitlesWidget: (value, meta) {
                if (value.toInt() < widget.analyticsData.pricePoints.length) {
                  final point = widget.analyticsData.pricePoints[value.toInt()];
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      DateFormat('MM/dd').format(point.timestamp),
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
              interval: _getPriceInterval(),
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
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        minX: 0,
        maxX: spots.isNotEmpty ? (spots.length - 1).toDouble() : 1,
        minY: _getMinY(),
        maxY: _getMaxY(),
        lineBarsData: [
          // Main line
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: _getLineColor(),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: _showDots || _touchedIndex != null,
              getDotPainter: (spot, percent, barData, index) {
                if (_touchedIndex == index) {
                  return FlDotCirclePainter(
                    radius: 6,
                    color: _getLineColor(),
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                }
                return FlDotCirclePainter(
                  radius: 3,
                  color: _getLineColor(),
                );
              },
            ),
            belowBarData: BarAreaData(
              show: _showArea,
              color: _getLineColor().withOpacity(0.1),
            ),
          ),
          // Comparison line
          if (comparisonSpots != null)
            LineChartBarData(
              spots: comparisonSpots,
              isCurved: true,
              color: Colors.purple,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(show: false),
              dashArray: [5, 5],
            ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((LineBarSpot touchedSpot) {
                final index = touchedSpot.x.toInt();
                if (index < widget.analyticsData.pricePoints.length) {
                  final point = widget.analyticsData.pricePoints[index];
                  return LineTooltipItem(
                    '${DateFormat('MM/dd HH:mm').format(point.timestamp)}\n₱${point.price.toStringAsFixed(2)}',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                }
                return null;
              }).toList();
            },
          ),
          touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
            if (event is FlTapUpEvent && touchResponse != null) {
              setState(() {
                _touchedIndex = touchResponse.lineBarSpots?[0].x.toInt();
              });
            } else if (event is FlPanEndEvent) {
              setState(() {
                _touchedIndex = null;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    final barGroups = widget.analyticsData.pricePoints.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value.price,
            color: _getBarColor(entry.value.price),
            width: 8,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(2),
              topRight: Radius.circular(2),
            ),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: _getMaxY(),
        minY: _getMinY(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _getPriceInterval(),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: _getXInterval(),
              getTitlesWidget: (value, meta) {
                if (value.toInt() < widget.analyticsData.pricePoints.length) {
                  final point = widget.analyticsData.pricePoints[value.toInt()];
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      DateFormat('MM/dd').format(point.timestamp),
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
              interval: _getPriceInterval(),
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
        ),
        borderData: FlBorderData(show: true),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final index = group.x.toInt();
              if (index < widget.analyticsData.pricePoints.length) {
                final point = widget.analyticsData.pricePoints[index];
                return BarTooltipItem(
                  '${DateFormat('MM/dd HH:mm').format(point.timestamp)}\n₱${point.price.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              }
              return null;
            },
          ),
        ),
        barGroups: barGroups,
      ),
    );
  }

  Widget _buildComparisonLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem('Current Station', _getLineColor()),
        const SizedBox(width: 16),
        _buildLegendItem('Comparison', Colors.purple),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildPriceChangeIndicator() {
    final change = widget.analyticsData.priceChange;
    final changePercent = widget.analyticsData.priceChangePercentage;
    final isIncreasing = widget.analyticsData.isPriceIncreasing;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isIncreasing ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isIncreasing ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildChangeItem(
            'Change',
            '${isIncreasing ? '+' : ''}₱${change.abs().toStringAsFixed(2)}',
            isIncreasing ? Colors.red : Colors.green,
            isIncreasing ? Icons.arrow_upward : Icons.arrow_downward,
          ),
          _buildChangeItem(
            'Change %',
            '${isIncreasing ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
            isIncreasing ? Colors.red : Colors.green,
            isIncreasing ? Icons.trending_up : Icons.trending_down,
          ),
          _buildChangeItem(
            'Trend',
            isIncreasing ? 'Increasing' : 'Decreasing',
            isIncreasing ? Colors.red : Colors.green,
            isIncreasing ? Icons.arrow_upward : Icons.arrow_downward,
          ),
        ],
      ),
    );
  }

  Widget _buildChangeItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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

  double _getMinY() {
    if (widget.analyticsData.pricePoints.isEmpty) return 0;
    final minPrice = widget.analyticsData.minPrice;
    return (minPrice * 0.95).clamp(0, double.infinity);
  }

  double _getMaxY() {
    if (widget.analyticsData.pricePoints.isEmpty) return 10;
    final maxPrice = widget.analyticsData.maxPrice;
    return (maxPrice * 1.05);
  }

  double _getPriceInterval() {
    final range = _getMaxY() - _getMinY();
    if (range < 5) return 0.5;
    if (range < 10) return 1.0;
    if (range < 20) return 2.0;
    return 5.0;
  }

  double _getXInterval() {
    final count = widget.analyticsData.pricePoints.length;
    if (count <= 7) return 1;
    if (count <= 14) return 2;
    if (count <= 30) return 5;
    return 10;
  }

  Color _getLineColor() {
    if (widget.analyticsData.priceChange == 0) return Colors.blue;
    return widget.analyticsData.isPriceIncreasing ? Colors.red : Colors.green;
  }

  Color _getBarColor(double price) {
    final avg = widget.analyticsData.averagePrice;
    if (price < avg * 0.95) return Colors.green;
    if (price > avg * 1.05) return Colors.red;
    return Colors.orange;
  }
}

