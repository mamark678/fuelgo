import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';

class AnalyticsSummaryWidget extends StatelessWidget {
  final List<AnalyticsData> analyticsData;
  final bool isLoading;

  const AnalyticsSummaryWidget({
    Key? key,
    required this.analyticsData,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (analyticsData.isEmpty) {
      return const SizedBox.shrink();
    }

    final summary = _calculateSummary();

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Summary Overview',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: _getCrossAxisCount(context),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildSummaryCard(
                context,
                'Total Stations',
                summary.totalStations.toString(),
                Icons.local_gas_station,
                Colors.blue,
              ),
              _buildSummaryCard(
                context,
                'Average Price',
                '\$${summary.averagePrice.toStringAsFixed(2)}',
                Icons.attach_money,
                Colors.green,
              ),
              _buildSummaryCard(
                context,
                'Price Range',
                '\$${summary.minPrice.toStringAsFixed(2)} - \$${summary.maxPrice.toStringAsFixed(2)}',
                Icons.trending_up,
                Colors.orange,
              ),
              _buildSummaryCard(
                context,
                'Active Trends',
                '${summary.increasingTrends}↑ ${summary.decreasingTrends}↓',
                Icons.analytics,
                Colors.purple,
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 4;
    if (width > 800) return 2;
    return 2; // Mobile: 2 columns
  }

  Widget _buildSummaryCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: color,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  _SummaryData _calculateSummary() {
    if (analyticsData.isEmpty) {
      return _SummaryData(
        totalStations: 0,
        averagePrice: 0.0,
        minPrice: 0.0,
        maxPrice: 0.0,
        increasingTrends: 0,
        decreasingTrends: 0,
      );
    }

    final prices = analyticsData.map((data) => data.currentPrice).toList();
    final averagePrice = prices.reduce((a, b) => a + b) / prices.length;
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);

    final increasingTrends = analyticsData.where((data) => data.isPriceIncreasing).length;
    final decreasingTrends = analyticsData.length - increasingTrends;

    // Get unique stations
    final uniqueStations = analyticsData.map((data) => data.stationId).toSet().length;

    return _SummaryData(
      totalStations: uniqueStations,
      averagePrice: averagePrice,
      minPrice: minPrice,
      maxPrice: maxPrice,
      increasingTrends: increasingTrends,
      decreasingTrends: decreasingTrends,
    );
  }
}

class _SummaryData {
  final int totalStations;
  final double averagePrice;
  final double minPrice;
  final double maxPrice;
  final int increasingTrends;
  final int decreasingTrends;

  _SummaryData({
    required this.totalStations,
    required this.averagePrice,
    required this.minPrice,
    required this.maxPrice,
    required this.increasingTrends,
    required this.decreasingTrends,
  });
}
