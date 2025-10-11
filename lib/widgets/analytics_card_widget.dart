import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';

class AnalyticsCardWidget extends StatelessWidget {
  final AnalyticsData analyticsData;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool compact; // New parameter for grid layout

  const AnalyticsCardWidget({
    Key? key,
    required this.analyticsData,
    this.onTap,
    this.isSelected = false,
    this.compact = false, // Default to false for backward compatibility
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: compact
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: isSelected ? Colors.blue[50] : null,
      elevation: isSelected ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: isSelected
                ? LinearGradient(
                    colors: [Colors.blue.shade50, Colors.blue.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with station name and fuel type
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      analyticsData.stationName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: compact ? 14 : 16,
                          ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getFuelTypeColor(analyticsData.fuelType).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getFuelTypeColor(analyticsData.fuelType).withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      analyticsData.fuelType.toUpperCase(),
                      style: TextStyle(
                        fontSize: compact ? 10 : 12,
                        fontWeight: FontWeight.bold,
                        color: _getFuelTypeColor(analyticsData.fuelType),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Current price with trend indicator
              Row(
                children: [
                  Text(
                    '\$${analyticsData.currentPrice.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getPriceColor(analyticsData.currentPrice),
                          fontSize: compact ? 18 : 20,
                        ),
                  ),
                  const SizedBox(width: 8),
                  _buildTrendIndicator(context),
                ],
              ),

              const SizedBox(height: 8),

              // Average price
              Text(
                'Avg: \$${analyticsData.averagePrice.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                      fontSize: compact ? 12 : 14,
                    ),
              ),

              const SizedBox(height: 8),

              // Stats row
              _buildStatsRow(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendIndicator(BuildContext context) {
    final isIncreasing = analyticsData.isPriceIncreasing;
    final changePercent = analyticsData.priceChangePercentage.abs();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isIncreasing ? Colors.red[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isIncreasing ? Icons.trending_up : Icons.trending_down,
            color: isIncreasing ? Colors.red : Colors.green,
            size: compact ? 14 : 16,
          ),
          const SizedBox(width: 2),
          Text(
            '${changePercent.toStringAsFixed(1)}%',
            style: TextStyle(
              color: isIncreasing ? Colors.red : Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 10 : 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(
            context,
            'Min',
            '\$${analyticsData.minPrice.toStringAsFixed(2)}',
            Colors.blue[600]!,
          ),
          Container(
            height: 20,
            width: 1,
            color: Colors.grey[300],
          ),
          _buildStatItem(
            context,
            'Max',
            '\$${analyticsData.maxPrice.toStringAsFixed(2)}',
            Colors.red[600]!,
          ),
          Container(
            height: 20,
            width: 1,
            color: Colors.grey[300],
          ),
          _buildStatItem(
            context,
            'Points',
            '${analyticsData.pricePoints.length}',
            Colors.purple[600]!,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: compact ? 10 : 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: compact ? 11 : 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getPriceColor(double price) {
    if (price < 2.5) return Colors.green;
    if (price < 3.0) return Colors.orange;
    return Colors.red;
  }

  Color _getFuelTypeColor(String fuelType) {
    switch (fuelType.toLowerCase()) {
      case 'regular':
        return Colors.blue[100]!;
      case 'midgrade':
        return Colors.orange[100]!;
      case 'premium':
        return Colors.purple[100]!;
      case 'diesel':
        return Colors.grey[300]!;
      default:
        return Colors.grey[200]!;
    }
  }
}
