import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'firestore_service.dart';

class UserPreferencesService extends ChangeNotifier {
  static final UserPreferencesService _instance = UserPreferencesService._internal();
  factory UserPreferencesService() => _instance;
  UserPreferencesService._internal() {
    // Initialize favorites after authentication check
    _initializeAfterAuth();
  }

  String get currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid ?? '';
  }

  // Default preferences
  String _preferredFuelType = 'Regular';
  final Set<String> _favoriteStationIds = {};
  StreamSubscription<List<String>>? _favoritesSubscription;
  StreamSubscription<User?>? _authStateSubscription;

  // Getters
  String get preferredFuelType => _preferredFuelType;
  Set<String> get favoriteStationIds => _favoriteStationIds;

  bool isFavorite(String stationId) {
    return _favoriteStationIds.contains(stationId);
  }

  // Initialize after authentication state is determined
  void _initializeAfterAuth() {
    // Listen to authentication state changes
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        // User is signed in, initialize favorites
        _initializeFavorites();
      } else {
        // User is signed out, clear favorites and cancel subscription
        _favoriteStationIds.clear();
        _favoritesSubscription?.cancel();
        _favoritesSubscription = null;
        notifyListeners();
      }
    });
  }

  // Initialize favorites from Firestore
  Future<void> _initializeFavorites() async {
    if (currentUserId.isEmpty) return;

    try {
      // Load initial favorites from Firestore
      final favorites = await FirestoreService.getUserFavorites(currentUserId);
      _favoriteStationIds.clear();
      _favoriteStationIds.addAll(favorites);
      notifyListeners();

      // Set up real-time listener for favorites
      _favoritesSubscription = FirestoreService.streamUserFavorites(currentUserId).listen(
        (favorites) {
          _favoriteStationIds.clear();
          _favoriteStationIds.addAll(favorites);
          notifyListeners();
        },
        onError: (error) {
          debugPrint('Error listening to favorites: $error');
        },
      );
    } catch (e) {
      debugPrint('Error initializing favorites: $e');
    }
  }

  // Setters
  void setPreferredFuelType(String fuelType) {
    if (_preferredFuelType != fuelType) {
      _preferredFuelType = fuelType;
      notifyListeners();
    }
  }

  Future<void> toggleFavoriteStation(String stationId) async {
    if (currentUserId.isEmpty) return;

    try {
      if (_favoriteStationIds.contains(stationId)) {
        await FirestoreService.removeFavorite(currentUserId, stationId);
        _favoriteStationIds.remove(stationId);
      } else {
        await FirestoreService.addFavorite(currentUserId, stationId);
        _favoriteStationIds.add(stationId);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      // Revert local change on error
      if (_favoriteStationIds.contains(stationId)) {
        _favoriteStationIds.remove(stationId);
      } else {
        _favoriteStationIds.add(stationId);
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _favoritesSubscription?.cancel();
    _authStateSubscription?.cancel();
    super.dispose();
  }
}
