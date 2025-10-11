import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FavoritesService {
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  /// Add a station to favorites
  Future<void> addFavorite(String stationName) async {
    if (_userId == null) throw Exception('User not authenticated');

    final favoriteData = {
      'stationName': stationName,
      'userId': _userId,
      'createdAt': FieldValue.serverTimestamp(),
    };

    // Use station name as document ID for easy lookup
    await _firestore
        .collection('user_favorites')
        .doc('$_userId\_$stationName')
        .set(favoriteData);
  }

  /// Remove a station from favorites
  Future<void> removeFavorite(String stationName) async {
    if (_userId == null) throw Exception('User not authenticated');

    await _firestore
        .collection('user_favorites')
        .doc('$_userId\_$stationName')
        .delete();
  }

  /// Check if a station is favorited
  Future<bool> isFavorite(String stationName) async {
    if (_userId == null) return false;

    final doc = await _firestore
        .collection('user_favorites')
        .doc('$_userId\_$stationName')
        .get();

    return doc.exists;
  }

  /// Get all favorite station names for current user
  Future<Set<String>> getFavorites() async {
    if (_userId == null) return {};

    final querySnapshot = await _firestore
        .collection('user_favorites')
        .where('userId', isEqualTo: _userId)
        .get();

    return querySnapshot.docs
        .map((doc) => doc.data()['stationName'] as String)
        .toSet();
  }

  /// Toggle favorite status for a station
  Future<bool> toggleFavorite(String stationName) async {
    if (_userId == null) throw Exception('User not authenticated');

    final currentlyFavorite = await isFavorite(stationName);

    if (currentlyFavorite) {
      await removeFavorite(stationName);
      return false; // Now not favorite
    } else {
      await addFavorite(stationName);
      return true; // Now favorite
    }
  }

  /// Listen to favorites changes in real-time
  Stream<Set<String>> getFavoritesStream() {
    if (_userId == null) return Stream.value({});

    return _firestore
        .collection('user_favorites')
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => doc.data()['stationName'] as String)
              .toSet();
        });
  }
}
