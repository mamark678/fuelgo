import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Get user data from users collection
  static Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final userDoc = await _db.collection('users').doc(userId).get();
      if (userDoc.exists) {
        return userDoc.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      // Handle permission errors gracefully
      if (e.toString().contains('PERMISSION_DENIED') || e.toString().contains('Missing or insufficient permissions')) {
        print('Permission denied accessing user data for: $userId');
        return null;
      }
      print('Error fetching user data: $e');
      return null;
    }
  }

  // Get user name from users collection
  static Future<String> getUserName(String userId) async {
    try {
      print('DEBUG: Fetching user name for userId: $userId');
      final userData = await getUserData(userId);
      print('DEBUG: User data retrieved: $userData');
      
      if (userData != null) {
        final name = userData['name'] ?? userData['displayName'] ?? 'Anonymous User';
        print('DEBUG: User name found: $name');
        return name;
      }
      
      print('DEBUG: No user data found for userId: $userId');
      return 'Anonymous User';
    } catch (e) {
      print('DEBUG: Error fetching user name for userId $userId: $e');
      return 'Anonymous User';
    }
  }

  // Stream user data for real-time updates
  static Stream<DocumentSnapshot> streamUserData(String userId) {
    return _db.collection('users').doc(userId).snapshots().handleError((error) {
      // Handle permission errors in stream
      if (error.toString().contains('PERMISSION_DENIED') || error.toString().contains('Missing or insufficient permissions')) {
        print('Permission denied streaming user data for: $userId');
      } else {
        print('Error streaming user data: $error');
      }
    });
  }

  // Batch fetch user names for multiple user IDs
  static Future<Map<String, String>> getUserNames(List<String> userIds) async {
    try {
      final userNames = <String, String>{};

      if (userIds.isEmpty) return userNames;

      final usersSnapshot = await _db
          .collection('users')
          .where(FieldPath.documentId, whereIn: userIds)
          .get();

      for (var doc in usersSnapshot.docs) {
        final data = doc.data();
        userNames[doc.id] = data['name'] ?? 'Anonymous User';
      }

      // Fill in missing user IDs with default names
      for (var userId in userIds) {
        if (!userNames.containsKey(userId)) {
          userNames[userId] = 'Anonymous User';
        }
      }

      return userNames;
    } catch (e) {
      // Handle permission errors gracefully
      if (e.toString().contains('PERMISSION_DENIED') || e.toString().contains('Missing or insufficient permissions')) {
        print('Permission denied batch fetching user names');
        return {for (var id in userIds) id: 'Anonymous User'};
      }
      print('Error batch fetching user names: $e');
      return {for (var id in userIds) id: 'Anonymous User'};
    }
  }
}
