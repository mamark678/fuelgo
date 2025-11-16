import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserInteractionService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Track when user views a station's prices
  static Future<void> trackPriceView({
    required String stationId,
    required String stationName,
    required String fuelType,
    required double price,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _db.collection('user_interactions').add({
        'userId': user.uid,
        'stationId': stationId,
        'stationName': stationName,
        'fuelType': fuelType,
        'price': price,
        'interactionType': 'price_view',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error tracking price view: $e');
    }
  }

  // Track when user clicks on a station
  static Future<void> trackStationClick({
    required String stationId,
    required String stationName,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _db.collection('user_interactions').add({
        'userId': user.uid,
        'stationId': stationId,
        'stationName': stationName,
        'interactionType': 'station_click',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error tracking station click: $e');
    }
  }

  // Track when user views analytics
  static Future<void> trackAnalyticsView({
    String? stationId,
    String? fuelType,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _db.collection('user_interactions').add({
        'userId': user.uid,
        if (stationId != null) 'stationId': stationId,
        if (fuelType != null) 'fuelType': fuelType,
        'interactionType': 'analytics_view',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error tracking analytics view: $e');
    }
  }

  // Track when user compares prices
  static Future<void> trackPriceComparison({
    required List<String> stationIds,
    required String fuelType,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _db.collection('user_interactions').add({
        'userId': user.uid,
        'stationIds': stationIds,
        'fuelType': fuelType,
        'interactionType': 'price_comparison',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error tracking price comparison: $e');
    }
  }

  // Get user interaction analytics
  static Future<Map<String, dynamic>> getUserInteractionAnalytics({
    String? stationId,
    int daysBack = 30,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {};

      final cutoffDate = DateTime.now().subtract(Duration(days: daysBack));
      Query query = _db.collection('user_interactions')
          .where('userId', isEqualTo: user.uid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoffDate));

      if (stationId != null) {
        query = query.where('stationId', isEqualTo: stationId);
      }

      final snapshot = await query.get();
      
      int priceViews = 0;
      int stationClicks = 0;
      int analyticsViews = 0;
      int priceComparisons = 0;
      final Map<String, int> fuelTypeViews = {};
      final Map<String, int> stationViews = {};

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        
        final interactionType = data['interactionType'] as String? ?? '';
        
        switch (interactionType) {
          case 'price_view':
            priceViews++;
            final fuelType = data['fuelType'] as String? ?? '';
            final stationId = data['stationId'] as String? ?? '';
            if (fuelType.isNotEmpty) {
              fuelTypeViews[fuelType] = (fuelTypeViews[fuelType] ?? 0) + 1;
            }
            if (stationId.isNotEmpty) {
              stationViews[stationId] = (stationViews[stationId] ?? 0) + 1;
            }
            break;
          case 'station_click':
            stationClicks++;
            break;
          case 'analytics_view':
            analyticsViews++;
            break;
          case 'price_comparison':
            priceComparisons++;
            break;
        }
      }

      return {
        'totalInteractions': snapshot.docs.length,
        'priceViews': priceViews,
        'stationClicks': stationClicks,
        'analyticsViews': analyticsViews,
        'priceComparisons': priceComparisons,
        'fuelTypeViews': fuelTypeViews,
        'stationViews': stationViews,
        'mostViewedFuelType': fuelTypeViews.isNotEmpty
            ? fuelTypeViews.entries.reduce((a, b) => a.value > b.value ? a : b).key
            : null,
        'mostViewedStation': stationViews.isNotEmpty
            ? stationViews.entries.reduce((a, b) => a.value > b.value ? a : b).key
            : null,
      };
    } catch (e) {
      print('Error getting user interaction analytics: $e');
      return {};
    }
  }

  // Get station popularity analytics (for admin/owners)
  static Future<Map<String, dynamic>> getStationPopularityAnalytics({
    required String stationId,
    int daysBack = 30,
  }) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysBack));
      final snapshot = await _db.collection('user_interactions')
          .where('stationId', isEqualTo: stationId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoffDate))
          .get();

      int totalViews = 0;
      int totalClicks = 0;
      final Map<String, int> fuelTypeViews = {};
      final Map<String, int> userViews = {};

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        
        final interactionType = data['interactionType'] as String? ?? '';
        final userId = data['userId'] as String? ?? '';
        final fuelType = data['fuelType'] as String? ?? '';

        if (interactionType == 'price_view') {
          totalViews++;
          if (fuelType.isNotEmpty) {
            fuelTypeViews[fuelType] = (fuelTypeViews[fuelType] ?? 0) + 1;
          }
        } else if (interactionType == 'station_click') {
          totalClicks++;
        }

        if (userId.isNotEmpty) {
          userViews[userId] = (userViews[userId] ?? 0) + 1;
        }
      }

      return {
        'totalViews': totalViews,
        'totalClicks': totalClicks,
        'uniqueUsers': userViews.length,
        'fuelTypeViews': fuelTypeViews,
        'mostViewedFuelType': fuelTypeViews.isNotEmpty
            ? fuelTypeViews.entries.reduce((a, b) => a.value > b.value ? a : b).key
            : null,
      };
    } catch (e) {
      print('Error getting station popularity analytics: $e');
      return {};
    }
  }
}

