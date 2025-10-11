import 'package:fuelgo/models/analytics_data.dart';
import 'package:fuelgo/models/price_history.dart';
import 'package:fuelgo/services/firestore_service.dart';

class AnalyticsService {
  // Get analytics data for a specific station and fuel type
  static Future<AnalyticsData> getStationAnalytics({
    required String stationId,
    required String stationName,
    String? fuelType,
    int daysBack = 30,
  }) async {
    try {
      print('DEBUG: Getting price history for station $stationId, fuelType: $fuelType');

      List<PriceHistory> history = [];

      if (fuelType != null && fuelType.isNotEmpty) {
        // Try multiple fuel type variants to handle different casing/naming in Firestore
        final fuelTypeVariants = [
          fuelType.toLowerCase(), // lowercase
          fuelType.substring(0, 1).toUpperCase() + fuelType.substring(1), // capitalized
          fuelType.toUpperCase(), // uppercase
          fuelType, // original
        ];

        for (final variant in fuelTypeVariants) {
          print('DEBUG: Trying fuel type variant: $variant');
          history = await FirestoreService.getPriceHistory(
            stationId: stationId,
            fuelType: variant,
            daysBack: daysBack,
          );

          if (history.isNotEmpty) {
            print('DEBUG: Found ${history.length} records with variant: $variant');
            break;
          }
        }
      } else {
        // No fuel type filter - get all price history for the station
        print('DEBUG: No fuel type filter - getting all price history for station');
        history = await FirestoreService.getPriceHistory(
          stationId: stationId,
          fuelType: null, // This will get all fuel types
          daysBack: daysBack,
        );
      }

      print('DEBUG: Retrieved ${history.length} price history records');
      if (history.isNotEmpty) {
        print('DEBUG: First record: ${history.first}');
        print('DEBUG: Last record: ${history.last}');
      }

      final analytics = AnalyticsData.fromPriceHistory(
        history,
        stationId,
        stationName,
        fuelType ?? 'all fuel types',
      );

      print('DEBUG: Analytics data created: $analytics');
      return analytics;
    } catch (e) {
      print('ERROR: Failed to get station analytics: $e');
      throw Exception('Failed to get station analytics: $e');
    }
  }

  // Get analytics data for all stations owned by a user
  static Future<List<AnalyticsData>> getOwnerAnalytics({
    required String ownerId,
    String? fuelType,
    int daysBack = 30,
  }) async {
    try {
      List<PriceHistory> history = [];

      if (fuelType != null) {
        // Try multiple fuel type variants to handle different casing/naming in Firestore
        final fuelTypeVariants = [
          fuelType.toLowerCase(), // lowercase
          fuelType.substring(0, 1).toUpperCase() + fuelType.substring(1), // capitalized
          fuelType.toUpperCase(), // uppercase
          fuelType, // original
        ];

        for (final variant in fuelTypeVariants) {
          print('DEBUG: Trying fuel type variant for owner analytics: $variant');
          history = await FirestoreService.getPriceHistoryByOwner(
            ownerId: ownerId,
            fuelType: variant,
            daysBack: daysBack,
          );

          if (history.isNotEmpty) {
            print('DEBUG: Found ${history.length} records with variant: $variant');
            break;
          }
        }
      } else {
        // No fuel type filter - get all price history
        history = await FirestoreService.getPriceHistoryByOwner(
          ownerId: ownerId,
          fuelType: null,
          daysBack: daysBack,
        );
      }

      // Group by station and fuel type
      final groupedData = <String, List<PriceHistory>>{};

      for (final record in history) {
        final key = '${record.stationId}_${record.fuelType}';
        if (!groupedData.containsKey(key)) {
          groupedData[key] = [];
        }
        groupedData[key]!.add(record);
      }

      final analyticsList = <AnalyticsData>[];

      for (final entry in groupedData.entries) {
        final parts = entry.key.split('_');
        final stationId = parts[0];
        final fuelType = parts[1];

        // Get station name from the first record
        final stationName = entry.value.first.stationName;

        final analytics = AnalyticsData.fromPriceHistory(
          entry.value,
          stationId,
          stationName,
          fuelType,
        );

        analyticsList.add(analytics);
      }

      return analyticsList;
    } catch (e) {
      throw Exception('Failed to get owner analytics: $e');
    }
  }

  // Get market trends across all stations
  static Future<List<AnalyticsData>> getMarketTrends({
    String? fuelType,
    int daysBack = 30,
  }) async {
    try {
      final history = await FirestoreService.getAllPriceHistory(
        fuelType: fuelType,
        daysBack: daysBack,
      );

      // Group by station and fuel type
      final groupedData = <String, List<PriceHistory>>{};
      
      for (final record in history) {
        final key = '${record.stationId}_${record.fuelType}';
        if (!groupedData.containsKey(key)) {
          groupedData[key] = [];
        }
        groupedData[key]!.add(record);
      }

      final analyticsList = <AnalyticsData>[];
      
      for (final entry in groupedData.entries) {
        final parts = entry.key.split('_');
        final stationId = parts[0];
        final fuelType = parts[1];
        
        // Get station name from the first record
        final stationName = entry.value.first.stationName;
        
        final analytics = AnalyticsData.fromPriceHistory(
          entry.value,
          stationId,
          stationName,
          fuelType,
        );
        
        analyticsList.add(analytics);
      }

      return analyticsList;
    } catch (e) {
      throw Exception('Failed to get market trends: $e');
    }
  }

  // Get price comparison between stations
  static Future<Map<String, List<AnalyticsData>>> getPriceComparison({
    required List<String> stationIds,
    String? fuelType,
    int daysBack = 7,
  }) async {
    try {
      final comparisonData = <String, List<AnalyticsData>>{};
      
      for (final stationId in stationIds) {
        final station = await FirestoreService.getGasStation(stationId);
        if (station != null) {
          final stationName = station['name']?.toString() ?? 'Unknown Station';
          
          final analytics = await getStationAnalytics(
            stationId: stationId,
            stationName: stationName,
            fuelType: fuelType ?? 'all fuel types',
            daysBack: daysBack,
          );
          
          comparisonData[stationId] = [analytics];
        }
      }
      
      return comparisonData;
    } catch (e) {
      throw Exception('Failed to get price comparison: $e');
    }
  }

  // Get best performing stations (lowest prices or best trends)
  static Future<List<AnalyticsData>> getBestPerformingStations({
    required String ownerId,
    String? fuelType,
    int daysBack = 7,
    int limit = 5,
  }) async {
    try {
      final analytics = await getOwnerAnalytics(
        ownerId: ownerId,
        fuelType: fuelType,
        daysBack: daysBack,
      );

      // Sort by current price (ascending) and then by positive trend
      analytics.sort((a, b) {
        if (a.currentPrice != b.currentPrice) {
          return a.currentPrice.compareTo(b.currentPrice);
        }
        // If prices are equal, prefer decreasing prices
        return b.isPriceIncreasing ? -1 : 1;
      });

      return analytics.take(limit).toList();
    } catch (e) {
      throw Exception('Failed to get best performing stations: $e');
    }
  }

  // Get worst performing stations (highest prices or negative trends)
  static Future<List<AnalyticsData>> getWorstPerformingStations({
    required String ownerId,
    String? fuelType,
    int daysBack = 7,
    int limit = 5,
  }) async {
    try {
      final analytics = await getOwnerAnalytics(
        ownerId: ownerId,
        fuelType: fuelType,
        daysBack: daysBack,
      );

      // Sort by current price (descending) and then by negative trend
      analytics.sort((a, b) {
        if (a.currentPrice != b.currentPrice) {
          return b.currentPrice.compareTo(a.currentPrice);
        }
        // If prices are equal, prefer increasing prices
        return a.isPriceIncreasing ? -1 : 1;
      });

      return analytics.take(limit).toList();
    } catch (e) {
      throw Exception('Failed to get worst performing stations: $e');
    }
  }

  // Get average market price for a fuel type
  static Future<double> getMarketAveragePrice({
    String? fuelType,
    int daysBack = 7,
  }) async {
    try {
      final analytics = await getMarketTrends(
        fuelType: fuelType,
        daysBack: daysBack,
      );

      if (analytics.isEmpty) return 0.0;

      final total = analytics.fold<double>(0.0, (sum, data) => sum + data.currentPrice);
      return total / analytics.length;
    } catch (e) {
      throw Exception('Failed to get market average price: $e');
    }
  }

  // Get price volatility (standard deviation) for a station
  static Future<double> getPriceVolatility({
    required String stationId,
    required String fuelType,
    int daysBack = 30,
  }) async {
    try {
      final analytics = await getStationAnalytics(
        stationId: stationId,
        stationName: '', // Will be overridden
        fuelType: fuelType,
        daysBack: daysBack,
      );

      if (analytics.pricePoints.length < 2) return 0.0;

      final prices = analytics.pricePoints.map((p) => p.price).toList();
      final mean = analytics.averagePrice;
      
      final variance = prices.fold<double>(0.0, (sum, price) {
        return sum + ((price - mean) * (price - mean));
      }) / prices.length;

      return variance;
    } catch (e) {
      throw Exception('Failed to get price volatility: $e');
    }
  }
}
