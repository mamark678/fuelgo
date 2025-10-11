import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserServiceFixed {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Get user data from users collection with proper error handling
  static Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final userDoc = await _db.collection('users').doc(userId).get();
      if (userDoc.exists) {
        return userDoc.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Error fetching user data: $e');
      return null;
    }
  }

  // Get user name from users collection - FIXED VERSION
  static Future<String> getUserName(String userId) async {
    try {
      if (userId.isEmpty) {
        return 'Unknown User';
      }
      
      final userData = await getUserData(userId);
      
      if (userData != null) {
        // Try to get name from Firestore
        final name = userData['name'] ?? userData['displayName'] ?? 'User';
        return name;
      }
      
      return 'User';
    } catch (e) {
      print('Error fetching user name: $e');
      return 'User';
    }
  }

  // Get user name with fallback to display name
  static Future<String> getUserDisplayName(String userId) async {
    try {
      final userData = await getUserData(userId);
      
      if (userData != null) {
        return userData['name'] ?? userData['displayName'] ?? 'User';
      }
      
      return 'User';
    } catch (e) {
      return 'User';
    }
  }

  // Batch fetch user names for multiple user IDs
  static Future<Map<String, String>> getUserNames(List<String> userIds) async {
    try {
      final userNames = <String, String>{};

      if (userIds.isEmpty) return userNames;

      // Remove empty user IDs
      final validUserIds = userIds.where((id) => id.isNotEmpty).toList();
      if (validUserIds.isEmpty) return userNames;

      // Check if user is authenticated before making the query
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('User not authenticated, cannot fetch user names');
        return {for (var id in userIds) id: 'User'};
      }

      final usersSnapshot = await _db
          .collection('users')
          .where(FieldPath.documentId, whereIn: validUserIds)
          .get();

      for (var doc in usersSnapshot.docs) {
        final data = doc.data();
        userNames[doc.id] = data['name'] ?? 'User';
      }

      // Fill missing user IDs
      for (var userId in validUserIds) {
        if (!userNames.containsKey(userId)) {
          userNames[userId] = 'User';
        }
      }

      return userNames;
    } catch (e) {
      print('Error batch fetching user names: $e');
      return {for (var id in userIds) id: 'User'};
    }
  }
}
