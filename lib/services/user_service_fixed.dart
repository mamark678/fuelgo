import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserServiceFixed {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Get user data from users collection with proper error handling
  static Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final userDoc = await _db.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data == null) return null;
        // Ensure proper typed map is returned
        return Map<String, dynamic>.from(data as Map);
      }
      return null;
    } catch (e) {
      // Handle permission errors gracefully - users may not have permission to read other user documents
      if (e.toString().contains('PERMISSION_DENIED') ||
          e.toString().contains('permission-denied') ||
          e.toString().contains('Missing or insufficient permissions')) {
        // This is expected - don't log as error
        return null;
      }
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

      QuerySnapshot usersSnapshot;
      try {
        usersSnapshot = await _db
            .collection('users')
            .where(FieldPath.documentId, whereIn: validUserIds)
            .get();
      } catch (error) {
        // Handle permission errors gracefully - users may not have permission to read all user documents
        if (error.toString().contains('PERMISSION_DENIED') ||
            error.toString().contains('permission-denied') ||
            error.toString().contains('Missing or insufficient permissions')) {
          print(
              'Permission denied fetching user names (this is expected for some users)');
          // Return default names for all user IDs
          return {for (var id in userIds) id: 'User'};
        }
        // Re-throw other errors
        throw error;
      }

      for (var doc in usersSnapshot.docs) {
        final dataObj = doc.data();
        // doc.data() can be Map<String, dynamic> or null depending on API/version, cast safely
        final Map<String, dynamic>? data =
            (dataObj is Map) ? Map<String, dynamic>.from(dataObj) : null;
        userNames[doc.id] = (data?['name'] as String?) ?? 'User';
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

  /// Get full user profile data
  static Future<Map<String, dynamic>> getUserProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();

      if (doc.exists) {
        final data = doc.data();
        return data != null ? Map<String, dynamic>.from(data) : {};
      }
      return {};
    } catch (e) {
      print('Error getting user profile: $e');
      return {};
    }
  }

  /// Update user profile (name, location, photoBase64)
  static Future<void> updateUserProfile({
    required String uid,
    String? name,
    String? location,
    String? photoBase64,
  }) async {
    try {
      final Map<String, dynamic> updates = {};

      if (name != null) updates['name'] = name;
      if (location != null) updates['location'] = location;
      if (photoBase64 != null) updates['photoBase64'] = photoBase64;

      if (updates.isNotEmpty) {
        await _db.collection('users').doc(uid).update(updates);
      }
    } catch (e) {
      print('Error updating user profile: $e');
      throw Exception('Failed to update profile: $e');
    }
  }
}
