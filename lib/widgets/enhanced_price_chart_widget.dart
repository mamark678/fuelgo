import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
  State<EnhancedPriceChartWidget> createState() =>
      _EnhancedPriceChartWidgetState();
}

class _EnhancedPriceChartWidgetState extends State<EnhancedPriceChartWidget> {
  bool _showDots = false;
  bool _showArea = true;
  String _chartType = 'line'; // 'line', 'bar'
  int? _touchedIndex;
  late FlutterTts _flutterTts;
  bool _isPlayingAudio = false;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setStartHandler(() {
      if (mounted) setState(() => _isPlayingAudio = true);
    });
    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isPlayingAudio = false);
    });
    _flutterTts.setErrorHandler((msg) {
      if (mounted) setState(() => _isPlayingAudio = false);
    });
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _speakSummary() async {
    if (_isPlayingAudio) {
      await _flutterTts.stop();
      return;
    }

    final data = widget.analyticsData;
    final trend = data.isPriceIncreasing ? "increasing" : "decreasing";
    final change = data.priceChange.abs().toStringAsFixed(2);
    final text = "Price trend for ${data.stationName} is $trend. "
        "The current price is ${data.currentPrice.toStringAsFixed(2)} pesos, "
        "which is a change of $change pesos. "
        "The average price over the period is ${data.averagePrice.toStringAsFixed(2)} pesos.";

    await _flutterTts.speak(text);
  }

  void _onChartTouch(FlTouchEvent event, LineTouchResponse? touchResponse) {
    if (!mounted) return;

    if (event is FlTapUpEvent && touchResponse?.lineBarSpots != null) {
      final index = touchResponse!.lineBarSpots![0].x.toInt();
      if (_touchedIndex != index) {
        setState(() => _touchedIndex = index);
        HapticFeedback.selectionClick();
        _speakPricePoint(index);
      }
    } else if (event is FlPanDownEvent || event is FlPanUpdateEvent) {
      if (touchResponse?.lineBarSpots != null) {
        final index = touchResponse!.lineBarSpots![0].x.toInt();
        if (_touchedIndex != index) {
          setState(() => _touchedIndex = index);
          HapticFeedback.selectionClick();
          // Optional: throttle speaking during drag if needed,
          // generally drag speaking can be annoying so dragging haptics is good enough
        }
      }
    } else if (event is FlPanEndEvent || event is FlTapUpEvent) {
      setState(() => _touchedIndex = null);
    }
  }

  Future<void> _speakPricePoint(int index) async {
    if (index < widget.analyticsData.pricePoints.length) {
      final point = widget.analyticsData.pricePoints[index];
      final date = DateFormat('MMMM d').format(point.timestamp);
      await _flutterTts
          .speak("On $date, price was ${point.price.toStringAsFixed(2)}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and audio control
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.showTitle)
                  Expanded(
                    child: Semantics(
                      label: "Station Name and Fuel Type",
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
                  ),
                // Controls
                Row(
                  children: [
                    IconButton(
                      icon: Icon(_isPlayingAudio
                          ? Icons.stop_circle
                          : Icons.volume_up),
                      onPressed: _speakSummary,
                      tooltip:
                          _isPlayingAudio ? 'Stop Audio' : 'Play Audio Summary',
                      color: _isPlayingAudio ? Colors.red : Colors.blue,
                    ),
                    IconButton(
                      icon: Icon(_chartType == 'line'
                          ? Icons.show_chart
                          : Icons.show_chart_outlined),
                      onPressed: () => setState(() => _chartType = 'line'),
                      tooltip: 'Line Chart',
                      color: _chartType == 'line' ? Colors.blue : Colors.grey,
                    ),
                    IconButton(
                      icon: Icon(_chartType == 'bar'
                          ? Icons.bar_chart
                          : Icons.bar_chart_outlined),
                      onPressed: () => setState(() => _chartType = 'bar'),
                      tooltip: 'Bar Chart',
                      color: _chartType == 'bar' ? Colors.blue : Colors.grey,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats cards
            _buildQuickStats(),
            const SizedBox(height: 24),

            // Chart
            Semantics(
              label: "Price History Chart. Double tap to hear summary.",
              onTap: _speakSummary,
              child: SizedBox(
                height: widget.chartHeight,
                child:
                    _chartType == 'line' ? _buildLineChart() : _buildBarChart(),
              ),
            ),

            // Legend and comparison toggle
            if (widget.showComparison && widget.comparisonData != null) ...[
              const SizedBox(height: 16),
              _buildComparisonLegend(),
            ],

            // Price change indicator
            const SizedBox(height: 16),
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

  Widget _buildStatCard(
      String label, String value, Color color, IconData icon) {
    return Semantics(
      label: "$label price is $value",
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart() {
    final spots = widget.analyticsData.pricePoints.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.price);
    }).toList();

    final comparisonSpots =
        widget.showComparison && widget.comparisonData != null
            ? widget.comparisonData!.pricePoints.asMap().entries.map((entry) {
                return FlSpot(entry.key.toDouble(), entry.value.price);
              }).toList()
            : null;

    final lineColor = _getLineColor();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _getPriceInterval(),
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.withOpacity(0.15),
              strokeWidth: 1,
              dashArray: [5, 5],
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
              reservedSize: 32,
              interval: _getXInterval(),
              getTitlesWidget: (value, meta) {
                if (value.toInt() < widget.analyticsData.pricePoints.length) {
                  final point = widget.analyticsData.pricePoints[value.toInt()];
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        DateFormat('MM/dd').format(point.timestamp),
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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
              interval: _getPriceInterval(),
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    '₱${value.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: spots.isNotEmpty ? (spots.length - 1).toDouble() : 1,
        minY: _getMinY(),
        maxY: _getMaxY(),
        lineBarsData: [
          // Main line
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: lineColor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: _showDots || _touchedIndex != null,
              getDotPainter: (spot, percent, barData, index) {
                if (_touchedIndex == index) {
                  return FlDotCirclePainter(
                    radius: 8,
                    color: lineColor,
                    strokeWidth: 3,
                    strokeColor: Colors.white,
                  );
                }
                return FlDotCirclePainter(
                  radius: 4,
                  color: lineColor.withOpacity(0.5),
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: _showArea,
              gradient: LinearGradient(
                colors: [
                  lineColor.withOpacity(0.4),
                  lineColor.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // Comparison line
          if (comparisonSpots != null)
            LineChartBarData(
              spots: comparisonSpots,
              isCurved: true,
              color: Colors.purple.withOpacity(0.6),
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(show: false),
              dashArray: [5, 5],
            ),
        ],
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((LineBarSpot touchedSpot) {
                final index = touchedSpot.x.toInt();
                if (index < widget.analyticsData.pricePoints.length) {
                  final point = widget.analyticsData.pricePoints[index];
                  return LineTooltipItem(
                    '${DateFormat('MMM dd').format(point.timestamp)}\n',
                    const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text: '₱${point.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  );
                }
                return null;
              }).toList();
            },
            tooltipRoundedRadius: 8,
            tooltipPadding: const EdgeInsets.all(12),
            tooltipMargin: 16,
          ),
          touchCallback: _onChartTouch,
          getTouchedSpotIndicator:
              (LineChartBarData barData, List<int> spotIndexes) {
            return spotIndexes.map((spotIndex) {
              return TouchedSpotIndicatorData(
                FlLine(color: Colors.grey.withOpacity(0.5), strokeWidth: 2),
                FlDotData(
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 8,
                      color: barData.color ?? Colors.blue,
                      strokeWidth: 3,
                      strokeColor: Colors.white,
                    );
                  },
                ),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    final barGroups =
        widget.analyticsData.pricePoints.asMap().entries.map((entry) {
      final isTouched = _touchedIndex == entry.key;
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value.price,
            color: isTouched
                ? Theme.of(context).primaryColor
                : _getBarColor(entry.value.price),
            width: isTouched ? 12 : 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: _getMaxY(),
              color: Colors.grey.withOpacity(0.1),
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
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
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
              interval: _getPriceInterval(),
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    '₱${value.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchCallback: (FlTouchEvent event, BarTouchResponse? touchResponse) {
            if (!mounted) return;
            if (event is FlTapUpEvent && touchResponse?.spot != null) {
              final index = touchResponse!.spot!.touchedBarGroupIndex;
              if (_touchedIndex != index) {
                setState(() => _touchedIndex = index);
                HapticFeedback.selectionClick();
                _speakPricePoint(index);
              }
            } else if (event is FlTapUpEvent) {
              setState(() => _touchedIndex = null);
            }
          },
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final index = group.x.toInt();
              if (index < widget.analyticsData.pricePoints.length) {
                final point = widget.analyticsData.pricePoints[index];
                return BarTooltipItem(
                  '${DateFormat('MMM d').format(point.timestamp)}\n',
                  const TextStyle(color: Colors.white70, fontSize: 12),
                  children: [
                    TextSpan(
                      text: '₱${point.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                );
              }
              return null;
            },
            tooltipRoundedRadius: 8,
            tooltipPadding: const EdgeInsets.all(12),
            tooltipMargin: 16,
          ),
        ),
        barGroups: barGroups,
      ),
    );
  }

  Widget _buildComparisonLegend() {
    return Semantics(
      label:
          "Legend: Blue line is current station, Purple dotted line is comparison",
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem('Current Station', _getLineColor()),
          const SizedBox(width: 16),
          _buildLegendItem('Comparison', Colors.purple, isDashed: true),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, {bool isDashed = false}) {
    return Row(
      children: [
        if (isDashed)
          Row(
            children: List.generate(
                3,
                (index) => Container(
                      width: 4,
                      height: 3,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )),
          )
        else
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

    // Semantics label construction
    final trendText = isIncreasing ? "increasing" : "decreasing";
    final changeText =
        "Price is $trendText by ${change.abs().toStringAsFixed(2)} pesos or ${changePercent.abs().toStringAsFixed(2)} percent.";

    return Semantics(
      label: changeText,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isIncreasing
                ? [Colors.red.withOpacity(0.1), Colors.red.withOpacity(0.02)]
                : [
                    Colors.green.withOpacity(0.1),
                    Colors.green.withOpacity(0.02)
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isIncreasing
                ? Colors.red.withOpacity(0.2)
                : Colors.green.withOpacity(0.2),
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
            Container(
                height: 30, width: 1, color: Colors.grey.withOpacity(0.2)),
            _buildChangeItem(
              'Change %',
              '${isIncreasing ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
              isIncreasing ? Colors.red : Colors.green,
              isIncreasing ? Icons.trending_up : Icons.trending_down,
            ),
            Container(
                height: 30, width: 1, color: Colors.grey.withOpacity(0.2)),
            _buildChangeItem(
              'Trend',
              isIncreasing ? 'Upward' : 'Downward',
              isIncreasing ? Colors.red : Colors.green,
              isIncreasing ? Icons.show_chart : Icons.show_chart,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangeItem(
      String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
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
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  double _getMinY() {
    if (widget.analyticsData.pricePoints.isEmpty) return 0;
    final minPrice = widget.analyticsData.minPrice;
    return (minPrice * 0.95).floorToDouble();
  }

  double _getMaxY() {
    if (widget.analyticsData.pricePoints.isEmpty) return 10;
    final maxPrice = widget.analyticsData.maxPrice;
    return (maxPrice * 1.05).ceilToDouble();
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
