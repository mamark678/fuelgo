// lib/services/gas_station_service.dart

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../models/gas_station.dart';
import '../models/offer.dart';
import '../models/voucher.dart';
import 'firestore_service.dart';

class GasStationService {
  static List<GasStation> _gasStations = [];
  static bool _isFetching = false;

  static List<GasStation> getAllGasStations() {
    return _gasStations;
  }

  static Future<void> fetchAndCacheGasStations({bool forceRefresh = false}) async {
    if ((_gasStations.isNotEmpty && !forceRefresh) || _isFetching) {
      print('[DEBUG] fetchAndCacheGasStations: Skipping fetch - cache exists and not force refresh, or already fetching');
      return;
    }
    _isFetching = true;

    print('[DEBUG] fetchAndCacheGasStations called, forceRefresh: $forceRefresh');
    print('[DEBUG] fetchAndCacheGasStations: Current cache size: ${_gasStations.length}');

    try {
      // Fetch from Firestore using the FirestoreService
      print('[DEBUG] fetchAndCacheGasStations: Calling FirestoreService.getAllGasStations()...');
      final firestoreStations = await FirestoreService.getAllGasStations();
      print('[DEBUG] fetchAndCacheGasStations: Received ${firestoreStations.length} stations from FirestoreService');

      if (firestoreStations.isNotEmpty) {
        final List<GasStation> stations = [];
        
        for (final stationData in firestoreStations) {
          try {
            print('[DEBUG] Parsing station: ${stationData['id']}');
            print('[DEBUG] Station data keys: ${stationData.keys.toList()}');
            print('[DEBUG] Station data types: ${stationData.map((k, v) => MapEntry(k, v.runtimeType))}');

            // Parse position
            double lat = 0.0;
            double lng = 0.0;

            final posRaw = stationData['position'];
            print('[DEBUG] Position raw type: ${posRaw.runtimeType}, value: $posRaw');

            if (posRaw is GeoPoint) {
              lat = posRaw.latitude;
              lng = posRaw.longitude;
            } else if (posRaw is Map) {
              lat = (posRaw['latitude'] ?? posRaw['lat'] ?? 0.0).toDouble();
              lng = (posRaw['longitude'] ?? posRaw['lng'] ?? posRaw['lon'] ?? 0.0).toDouble();
            } else if (stationData['latitude'] != null && stationData['longitude'] != null) {
              lat = (stationData['latitude'] as num).toDouble();
              lng = (stationData['longitude'] as num).toDouble();
            }

            // Parse prices
            final pricesRaw = stationData['prices'] ?? {};
            final Map<String, double> prices = {};
            if (pricesRaw is Map) {
              pricesRaw.forEach((key, value) {
                if (value != null) {
                  if (value is num) {
                    prices[key.toString()] = value.toDouble();
                  } else if (value is String) {
                    final parsed = double.tryParse(value);
                    if (parsed != null) prices[key.toString()] = parsed;
                  }
                }
              });
            }

            // Parse price reductions
            final priceReductionsRaw = stationData['priceReductions'] ?? {};
            final Map<String, double> priceReductions = {};
            if (priceReductionsRaw is Map) {
              priceReductionsRaw.forEach((key, value) {
                if (value != null) {
                  if (value is num) {
                    priceReductions[key.toString()] = value.toDouble();
                  } else if (value is String) {
                    final parsed = double.tryParse(value);
                    if (parsed != null) priceReductions[key.toString()] = parsed;
                  }
                }
              });
            }

            // Parse offers
            final offersRaw = stationData['offers'] ?? [];
            final List<Offer> offers = [];
            if (offersRaw is List) {
              print('[DEBUG] Parsing ${offersRaw.length} offers for station ${stationData['id']}');
              for (final offerData in offersRaw) {
                print('[DEBUG] Offer data type: ${offerData.runtimeType}, value: $offerData');
                if (offerData is Map<String, dynamic>) {
                  try {
                    final offer = Offer.fromMap(offerData);
                    offers.add(offer);
                  } catch (e) {
                    print('Error parsing offer: $e');
                  }
                } else {
                  print('[DEBUG] Skipping offer - not a Map: $offerData');
                }
              }
            }

            // Parse vouchers
            final vouchersRaw = stationData['vouchers'] ?? [];
            final List<Voucher> vouchers = [];
            if (vouchersRaw is List) {
              print('[DEBUG] Parsing ${vouchersRaw.length} vouchers for station ${stationData['id']}');
              for (final voucherData in vouchersRaw) {
                print('[DEBUG] Voucher data type: ${voucherData.runtimeType}, value: $voucherData');
                if (voucherData is Map<String, dynamic>) {
                  try {
                    final voucher = Voucher.fromMap(voucherData);
                    vouchers.add(voucher);
                  } catch (e) {
                    print('Error parsing voucher: $e');
                  }
                } else {
                  print('[DEBUG] Skipping voucher - not a Map: $voucherData');
                }
              }
            }

            // Parse amenities with debug logging
            final amenitiesRaw = stationData['amenities'] ?? [];
            final List<dynamic> amenities = [];
            if (amenitiesRaw is List) {
              print('[DEBUG] Parsing ${amenitiesRaw.length} amenities for station ${stationData['id']}');
              for (final amenityData in amenitiesRaw) {
                print('[DEBUG] Amenity data type: ${amenityData.runtimeType}, value: $amenityData');
                if (amenityData is Map<String, dynamic>) {
                  amenities.add(amenityData);
                } else if (amenityData is String) {
                  amenities.add(amenityData);
                } else {
                  print('[DEBUG] Skipping amenity - not a Map or String: $amenityData');
                }
              }
            }

            stations.add(GasStation(
              id: stationData['id']?.toString() ?? stationData['name']?.toString() ?? '',
              name: stationData['name'] ?? 'Unnamed Gas Station',
              position: LatLng(lat, lng),
              brand: stationData['brand'] ?? 'Unknown',
              address: stationData['address'] ?? 'Address not available',
              prices: prices,
              priceReductions: priceReductions,
              services: List<String>.from(stationData['services'] ?? []),
              rating: (stationData['rating'] ?? 0.0).toDouble(),
              isOpen: stationData['isOpen'] ?? true,
              offers: offers,
              vouchers: vouchers,
              isOwnerCreated: stationData['isOwnerCreated'] ?? false,
              ownerId: stationData['ownerId']?.toString(),
              amenities: amenities,
            ));
          } catch (e) {
            print('Error parsing station: $e');
            continue;
          }
        }

        _gasStations = stations;
        print('[DEBUG] Loaded ${stations.length} gas stations from Firestore');
        print('[DEBUG] Station IDs: ${stations.map((s) => s.id).toList()}');
        print('[DEBUG] Checking for specific station FG2025-506562: ${stations.any((s) => s.id == 'FG2025-506562')}');
      } else {
        // Fallback to sample data if no stations in Firestore
        _gasStations = _getSampleGasStations();
        print('[DEBUG] Using sample gas stations (no stations in Firestore)');
      }
    } catch (e) {
      print('[ERROR] Error loading gas stations: $e');
      _gasStations = _getSampleGasStations();
    } finally {
      _isFetching = false;
    }
  }

  // Clear the cache to force refresh on next call
  static void clearCache() {
    _gasStations = [];
    print('[DEBUG] GasStationService cache cleared');
  }

  static List<GasStation> _getSampleGasStations() {
    return [
      GasStation(
        id: '1',
        name: 'Shell Valencia',
        position: const LatLng(7.9055, 125.0908),
        brand: 'Shell',
        address: 'Valencia City, Bukidnon',
        prices: {'Regular': 60.50, 'Premium': 65.20, 'Diesel': 55.80},
        rating: 4.5,
        isOpen: true,
        services: ['Convenience Store', 'Car Wash', 'ATM'],
        amenities: [{'name': 'Restroom', 'type': 'facility'}],
        offers: [],
        vouchers: [],
      ),
      GasStation(
        id: '2',
        name: 'Petron Malaybalay',
        position: const LatLng(8.1555, 125.1308),
        brand: 'Petron',
        address: 'Malaybalay City, Bukidnon',
        prices: {'Regular': 59.80, 'Premium': 64.50, 'Diesel': 54.90},
        rating: 4.2,
        isOpen: true,
        services: ['Convenience Store', '24/7 Service'],
        amenities: [{'name': 'Restroom', 'type': 'facility'}],
        offers: [],
        vouchers: [],
      ),
    ];
  }

  // Helper to generate some random prices as a fallback
  static Map<String, double> _generateFuelPrices() {
    final random = math.Random();
    return {
      'Regular': 60 + random.nextDouble() * 5,
      'Premium': 65 + random.nextDouble() * 5,
      'Diesel': 55 + random.nextDouble() * 5,
    };
  }

  // Get gas stations by brand
  static List<GasStation> getGasStationsByBrand(String brand) {
    return _gasStations.where((station) => station.brand?.toLowerCase() == brand.toLowerCase()).toList();
  }

  // Get gas stations sorted by price (lowest first)
  static List<GasStation> getGasStationsByPrice() {
    List<GasStation> sorted = List.from(_gasStations);
    sorted.sort((a, b) {
      final double priceA = a.priceAsDouble;
      final double priceB = b.priceAsDouble;
      return priceA.compareTo(priceB);
    });
    return sorted;
  }

  // Get gas stations sorted by rating (highest first)
  static List<GasStation> getGasStationsByRating() {
    List<GasStation> sorted = List.from(_gasStations);
    sorted.sort((a, b) {
      final ratingA = a.rating ?? 0.0;
      final ratingB = b.rating ?? 0.0;
      return ratingB.compareTo(ratingA);
    });
    return sorted;
  }

  // Search gas stations by name
  static List<GasStation> searchGasStations(String query) {
    return _gasStations
        .where((station) =>
            station.name?.toLowerCase().contains(query.toLowerCase()) == true ||
            station.brand?.toLowerCase().contains(query.toLowerCase()) == true)
        .toList();
  }

  // Get nearest gas stations to a location
  static List<GasStation> getNearestGasStations(LatLng location, {int limit = 5}) {
    List<GasStation> sorted = List.from(_gasStations);
    sorted.sort((a, b) {
      double distanceA = calculateDistance(location, a.position);
      double distanceB = calculateDistance(location, b.position);
      return distanceA.compareTo(distanceB);
    });
    return sorted.take(limit).toList();
  }

  // Calculate distance between two points (Haversine formula)
  static double calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // kilometers

    double lat1 = point1.latitude * (math.pi / 180);
    double lat2 = point2.latitude * (math.pi / 180);
    double deltaLat = (point2.latitude - point1.latitude) * (math.pi / 180);
    double deltaLng = (point2.longitude - point1.longitude) * (math.pi / 180);

    double a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(deltaLng / 2) * math.sin(deltaLng / 2);
    double c = 2 * math.atan(math.sqrt(a) / math.sqrt(1 - a));

    return earthRadius * c;
  }

  // Get unique brands
  static List<String> getUniqueBrands() {
    return _gasStations.map((station) => station.brand).whereType<String>().toSet().toList();
  }

  // Get average price (safe with empty list)
  static double getAveragePrice() {
    if (_gasStations.isEmpty) return 0.0;
    double total = _gasStations.fold(0.0, (sum, station) => sum + (station.priceAsDouble ?? 0.0));
    return total / _gasStations.length;
  }

  // Get cheapest gas station
  static GasStation? getCheapestGasStation() {
    if (_gasStations.isEmpty) return null;

    return _gasStations.reduce((a, b) {
      final priceA = a.priceAsDouble ?? double.infinity;
      final priceB = b.priceAsDouble ?? double.infinity;
      return priceA < priceB ? a : b;
    });
  }

  // Get highest rated gas station
  static GasStation? getHighestRatedGasStation() {
    if (_gasStations.isEmpty) return null;

    return _gasStations.reduce((a, b) {
      final ratingA = a.rating ?? 0.0;
      final ratingB = b.rating ?? 0.0;
      return ratingA > ratingB ? a : b;
    });
  }

  // Update rating for a gas station
  static void updateGasStationRating(String stationId, double newRating) {
    try {
      final station = _gasStations.firstWhere((s) => s.id == stationId);
      station.rating = newRating;
    } catch (e) {
      print('Error updating rating for $stationId: $e');
    }
  }
}
