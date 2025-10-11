import './price_history.dart';

class AnalyticsData {
  final String stationId;
  final String stationName;
  final String fuelType;
  final List<PricePoint> pricePoints;
  final double currentPrice;
  final double averagePrice;
  final double minPrice;
  final double maxPrice;
  final double priceChange;
  final double priceChangePercentage;
  final bool isPriceIncreasing;

  AnalyticsData({
    required this.stationId,
    required this.stationName,
    required this.fuelType,
    required this.pricePoints,
    required this.currentPrice,
    required this.averagePrice,
    required this.minPrice,
    required this.maxPrice,
    required this.priceChange,
    required this.priceChangePercentage,
    required this.isPriceIncreasing,
  });

  factory AnalyticsData.fromPriceHistory(
    List<PriceHistory> history,
    String stationId,
    String stationName,
    String fuelType,
  ) {
    if (history.isEmpty) {
      return AnalyticsData(
        stationId: stationId,
        stationName: stationName,
        fuelType: fuelType,
        pricePoints: [],
        currentPrice: 0.0,
        averagePrice: 0.0,
        minPrice: 0.0,
        maxPrice: 0.0,
        priceChange: 0.0,
        priceChangePercentage: 0.0,
        isPriceIncreasing: false,
      );
    }

    // Sort by timestamp
    history.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final pricePoints = history.map((h) => PricePoint(
          price: h.price,
          timestamp: h.timestamp,
        )).toList();

    final currentPrice = pricePoints.last.price;
    final previousPrice = pricePoints.length > 1 ? pricePoints[pricePoints.length - 2].price : currentPrice;
    
    final prices = pricePoints.map((p) => p.price).toList();
    final averagePrice = prices.reduce((a, b) => a + b) / prices.length;
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    
    final priceChange = currentPrice - previousPrice;
    final priceChangePercentage = previousPrice > 0 ? (priceChange / previousPrice) * 100 : 0.0;
    final isPriceIncreasing = priceChange > 0;

    return AnalyticsData(
      stationId: stationId,
      stationName: stationName,
      fuelType: fuelType,
      pricePoints: pricePoints,
      currentPrice: currentPrice,
      averagePrice: averagePrice,
      minPrice: minPrice,
      maxPrice: maxPrice,
      priceChange: priceChange,
      priceChangePercentage: priceChangePercentage,
      isPriceIncreasing: isPriceIncreasing,
    );
  }

  @override
  String toString() {
    return 'AnalyticsData(station: $stationName, fuelType: $fuelType, currentPrice: $currentPrice, change: ${priceChangePercentage.toStringAsFixed(1)}%)';
  }
}

class PricePoint {
  final double price;
  final DateTime timestamp;

  PricePoint({
    required this.price,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'PricePoint(price: $price, timestamp: $timestamp)';
  }
}
