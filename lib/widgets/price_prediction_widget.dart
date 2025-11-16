import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';
import 'package:intl/intl.dart';

class PricePredictionWidget extends StatelessWidget {
  final AnalyticsData analyticsData;
  final int predictionDays;

  const PricePredictionWidget({
    Key? key,
    required this.analyticsData,
    this.predictionDays = 7,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final prediction = _calculatePrediction();
    final trend = _calculateTrend();

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
                const Icon(Icons.trending_up, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Price Prediction',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Prediction Summary
            _buildPredictionSummary(prediction, trend),
            const SizedBox(height: 16),
            
            // Prediction Chart
            SizedBox(
              height: 200,
              child: _buildPredictionChart(prediction, trend),
            ),
            
            const SizedBox(height: 16),
            
            // Prediction Details
            _buildPredictionDetails(prediction, trend),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _calculatePrediction() {
    if (analyticsData.pricePoints.length < 2) {
      return {
        'predictedPrice': analyticsData.currentPrice,
        'confidence': 0.0,
        'trend': 'stable',
      };
    }

    // Simple linear regression for prediction
    final prices = analyticsData.pricePoints.map((p) => p.price).toList();
    final n = prices.length;
    
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += prices[i];
      sumXY += i * prices[i];
      sumX2 += i * i;
    }
    
    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final intercept = (sumY - slope * sumX) / n;
    
    final predictedPrice = slope * (n + predictionDays) + intercept;
    final confidence = _calculateConfidence(prices);
    
    return {
      'predictedPrice': predictedPrice.clamp(0, double.infinity),
      'confidence': confidence,
      'trend': slope > 0.1 ? 'increasing' : slope < -0.1 ? 'decreasing' : 'stable',
      'slope': slope,
    };
  }

  double _calculateConfidence(List<double> prices) {
    if (prices.length < 3) return 0.5;
    
    // Calculate variance
    final mean = prices.reduce((a, b) => a + b) / prices.length;
    final variance = prices.fold<double>(0.0, (sum, price) {
      return sum + ((price - mean) * (price - mean));
    }) / prices.length;
    
    // Lower variance = higher confidence
    final stdDev = math.sqrt(variance);
    final confidence = 1.0 - (stdDev / mean).clamp(0.0, 1.0);
    
    return confidence.clamp(0.0, 1.0);
  }

  Map<String, dynamic> _calculateTrend() {
    if (analyticsData.pricePoints.length < 2) {
      return {
        'direction': 'stable',
        'strength': 0.0,
      };
    }

    final recentPrices = analyticsData.pricePoints
        .skip(analyticsData.pricePoints.length - 7)
        .map((p) => p.price)
        .toList();
    
    if (recentPrices.length < 2) {
      return {
        'direction': 'stable',
        'strength': 0.0,
      };
    }

    final firstPrice = recentPrices.first;
    final lastPrice = recentPrices.last;
    final change = lastPrice - firstPrice;
    final changePercent = (change / firstPrice) * 100;

    String direction;
    if (changePercent > 2) {
      direction = 'increasing';
    } else if (changePercent < -2) {
      direction = 'decreasing';
    } else {
      direction = 'stable';
    }

    return {
      'direction': direction,
      'strength': changePercent.abs(),
      'change': change,
      'changePercent': changePercent,
    };
  }

  Widget _buildPredictionSummary(Map<String, dynamic> prediction, Map<String, dynamic> trend) {
    final predictedPrice = prediction['predictedPrice'] as double;
    final confidence = prediction['confidence'] as double;
    final trendDirection = trend['direction'] as String;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text(
                  'Predicted Price',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₱${predictedPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                Text(
                  'in $predictionDays days',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _getTrendColor(trendDirection).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _getTrendColor(trendDirection).withOpacity(0.3),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'Trend',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  _getTrendIcon(trendDirection),
                  color: _getTrendColor(trendDirection),
                  size: 24,
                ),
                Text(
                  trendDirection.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getTrendColor(trendDirection),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text(
                  'Confidence',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(confidence * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                LinearProgressIndicator(
                  value: confidence,
                  backgroundColor: Colors.orange.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPredictionChart(Map<String, dynamic> prediction, Map<String, dynamic> trend) {
    final historicalSpots = analyticsData.pricePoints.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.price);
    }).toList();

    final predictedPrice = prediction['predictedPrice'] as double;
    final lastIndex = historicalSpots.length - 1;
    final predictionSpots = [
      FlSpot(lastIndex.toDouble(), analyticsData.currentPrice),
      FlSpot((lastIndex + predictionDays).toDouble(), predictedPrice),
    ];

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < analyticsData.pricePoints.length) {
                  final point = analyticsData.pricePoints[value.toInt()];
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      DateFormat('MM/dd').format(point.timestamp),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                if (value.toInt() == analyticsData.pricePoints.length + predictionDays - 1) {
                  return const SideTitleWidget(
                    axisSide: AxisSide.bottom,
                    child: Text(
                      'Predicted',
                      style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
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
        ),
        borderData: FlBorderData(show: true),
        minX: 0,
        maxX: (analyticsData.pricePoints.length + predictionDays - 1).toDouble(),
        minY: _getMinY(),
        maxY: _getMaxY(predictedPrice),
        lineBarsData: [
          // Historical data
          LineChartBarData(
            spots: historicalSpots,
            isCurved: true,
            color: Colors.blue,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
          // Prediction line
          LineChartBarData(
            spots: predictionSpots,
            isCurved: false,
            color: Colors.orange,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: true),
            dashArray: [5, 5],
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionDetails(Map<String, dynamic> prediction, Map<String, dynamic> trend) {
    final predictedPrice = prediction['predictedPrice'] as double;
    final currentPrice = analyticsData.currentPrice;
    final priceChange = predictedPrice - currentPrice;
    final priceChangePercent = (priceChange / currentPrice) * 100;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prediction Details',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _buildDetailRow('Current Price', '₱${currentPrice.toStringAsFixed(2)}'),
          _buildDetailRow('Predicted Price', '₱${predictedPrice.toStringAsFixed(2)}'),
          _buildDetailRow(
            'Expected Change',
            '${priceChange >= 0 ? '+' : ''}₱${priceChange.abs().toStringAsFixed(2)} (${priceChangePercent >= 0 ? '+' : ''}${priceChangePercent.toStringAsFixed(2)}%)',
            priceChange >= 0 ? Colors.red : Colors.green,
          ),
          _buildDetailRow('Trend', trend['direction'].toString().toUpperCase()),
          _buildDetailRow('Confidence', '${((prediction['confidence'] as double) * 100).toStringAsFixed(1)}%'),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  double _getMinY() {
    final minPrice = analyticsData.minPrice;
    final predictedPrice = _calculatePrediction()['predictedPrice'] as double;
    return (minPrice < predictedPrice ? minPrice : predictedPrice) * 0.95;
  }

  double _getMaxY(double predictedPrice) {
    final maxPrice = analyticsData.maxPrice;
    return (maxPrice > predictedPrice ? maxPrice : predictedPrice) * 1.05;
  }

  Color _getTrendColor(String direction) {
    switch (direction) {
      case 'increasing':
        return Colors.red;
      case 'decreasing':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  IconData _getTrendIcon(String direction) {
    switch (direction) {
      case 'increasing':
        return Icons.arrow_upward;
      case 'decreasing':
        return Icons.arrow_downward;
      default:
        return Icons.trending_flat;
    }
  }
}

