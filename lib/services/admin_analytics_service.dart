import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';

class AdminAnalyticsService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Get overall dashboard statistics
  static Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      // Get all users
      final usersSnapshot = await _db.collection('users').get();
      final users = usersSnapshot.docs;
      
      // Get all gas stations
      final stationsSnapshot = await _db.collection('gas_stations').get();
      final stations = stationsSnapshot.docs;
      
      // Calculate user statistics
      int totalUsers = users.length;
      int totalOwners = 0;
      int totalCustomers = 0;
      int pendingApprovals = 0;
      int approvedOwners = 0;
      int rejectedOwners = 0;
      int requestSubmission = 0;
      
      for (final userDoc in users) {
        final userData = userDoc.data();
        final role = userData['role'] as String? ?? 'customer';
        final approvalStatus = userData['approvalStatus'] as String? ?? '';
        
        if (role == 'owner') {
          totalOwners++;
          if (approvalStatus == 'pending') {
            pendingApprovals++;
          } else if (approvalStatus == 'approved') {
            approvedOwners++;
          } else if (approvalStatus == 'rejected') {
            rejectedOwners++;
          } else if (approvalStatus == 'request_submission') {
            requestSubmission++;
          }
        } else if (role == 'customer' || role == 'user') {
          totalCustomers++;
        }
      }
      
      // Calculate station statistics
      int totalStations = stations.length;
      int activeStations = 0;
      int ownerCreatedStations = 0;
      
      // Calculate offers and vouchers statistics
      int totalOffers = 0;
      int activeOffers = 0;
      int totalVouchers = 0;
      int activeVouchers = 0;
      
      for (final stationDoc in stations) {
        final stationData = stationDoc.data();
        final isOpen = stationData['isOpen'] as bool? ?? true;
        final isOwnerCreated = stationData['isOwnerCreated'] as bool? ?? false;
        
        if (isOpen) activeStations++;
        if (isOwnerCreated) ownerCreatedStations++;
        
        // Count offers
        final offers = List<Map<String, dynamic>>.from(stationData['offers'] ?? []);
        totalOffers += offers.length;
        for (final offer in offers) {
          final status = offer['status'] as String? ?? 'Active';
          if (status == 'Active') activeOffers++;
        }
        
        // Count vouchers
        final vouchers = List<Map<String, dynamic>>.from(stationData['vouchers'] ?? []);
        totalVouchers += vouchers.length;
        for (final voucher in vouchers) {
          final status = voucher['status'] as String? ?? 'Active';
          if (status == 'Active') activeVouchers++;
        }
      }
      
      // Get price history statistics
      final priceHistory = await FirestoreService.getAllPriceHistory(daysBack: 30);
      int totalPriceUpdates = priceHistory.length;
      
      // Calculate average prices by fuel type
      final Map<String, List<double>> pricesByFuelType = {};
      for (final history in priceHistory) {
        if (!pricesByFuelType.containsKey(history.fuelType)) {
          pricesByFuelType[history.fuelType] = [];
        }
        pricesByFuelType[history.fuelType]!.add(history.price);
      }
      
      final Map<String, double> averagePrices = {};
      pricesByFuelType.forEach((fuelType, prices) {
        if (prices.isNotEmpty) {
          averagePrices[fuelType] = prices.reduce((a, b) => a + b) / prices.length;
        }
      });
      
      // Get recent activity (last 7 days)
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      int recentRegistrations = 0;
      int recentPriceUpdates = 0;
      
      for (final userDoc in users) {
        final userData = userDoc.data();
        final createdAt = userData['createdAt'] as Timestamp?;
        if (createdAt != null && createdAt.toDate().isAfter(sevenDaysAgo)) {
          recentRegistrations++;
        }
      }
      
      for (final history in priceHistory) {
        if (history.timestamp.isAfter(sevenDaysAgo)) {
          recentPriceUpdates++;
        }
      }
      
      return {
        'totalUsers': totalUsers,
        'totalOwners': totalOwners,
        'totalCustomers': totalCustomers,
        'pendingApprovals': pendingApprovals,
        'approvedOwners': approvedOwners,
        'rejectedOwners': rejectedOwners,
        'requestSubmission': requestSubmission,
        'totalStations': totalStations,
        'activeStations': activeStations,
        'ownerCreatedStations': ownerCreatedStations,
        'totalOffers': totalOffers,
        'activeOffers': activeOffers,
        'totalVouchers': totalVouchers,
        'activeVouchers': activeVouchers,
        'totalPriceUpdates': totalPriceUpdates,
        'averagePrices': averagePrices,
        'recentRegistrations': recentRegistrations,
        'recentPriceUpdates': recentPriceUpdates,
      };
    } catch (e) {
      throw Exception('Failed to get dashboard stats: $e');
    }
  }

  // Get registration trends (last 30 days)
  static Future<Map<String, int>> getRegistrationTrends() async {
    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final usersSnapshot = await _db.collection('users')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .get();
      
      final Map<String, int> trends = {};
      
      for (final userDoc in usersSnapshot.docs) {
        final userData = userDoc.data();
        final createdAt = userData['createdAt'] as Timestamp?;
        if (createdAt != null) {
          final dateKey = '${createdAt.toDate().year}-${createdAt.toDate().month.toString().padLeft(2, '0')}-${createdAt.toDate().day.toString().padLeft(2, '0')}';
          trends[dateKey] = (trends[dateKey] ?? 0) + 1;
        }
      }
      
      return trends;
    } catch (e) {
      throw Exception('Failed to get registration trends: $e');
    }
  }

  // Get price trends by fuel type (last 30 days)
  static Future<Map<String, List<Map<String, dynamic>>>> getPriceTrends() async {
    try {
      final priceHistory = await FirestoreService.getAllPriceHistory(daysBack: 30);
      
      final Map<String, List<Map<String, dynamic>>> trends = {};
      
      for (final history in priceHistory) {
        if (!trends.containsKey(history.fuelType)) {
          trends[history.fuelType] = [];
        }
        trends[history.fuelType]!.add({
          'price': history.price,
          'timestamp': history.timestamp,
          'stationName': history.stationName,
        });
      }
      
      // Sort by timestamp
      trends.forEach((fuelType, data) {
        data.sort((a, b) => (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime));
      });
      
      return trends;
    } catch (e) {
      throw Exception('Failed to get price trends: $e');
    }
  }
}

