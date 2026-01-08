import 'dart:math';

import 'package:latlong2/latlong.dart'; // <-- Use latlong2 for LatLng

class GasStation {
  final String? id;
  final String? name;
  final LatLng position;
  final String? brand;
  final Map<String, double>? prices;
  final Map<String, double>? priceReductions;
  final Map<String, Map<String, dynamic>>? fuelPerformance;
  double? rating;
  final bool isOpen;
  final String? address;
  final List<dynamic>? offers;
  final List<dynamic>? vouchers;
  final List<String>? services;
  final bool? isOwnerCreated;
  final String? ownerId;
  final List<dynamic> amenities;
  final Map<String, dynamic>? ratings;

  // Mutable averageRating field
  double? averageRating;

  GasStation({
    this.id,
    this.name,
    required this.position,
    this.brand,
    this.prices,
    this.priceReductions,
    this.fuelPerformance,
    this.rating,
    this.isOpen = true,
    this.address,
    this.offers,
    this.vouchers,
    this.services,
    this.isOwnerCreated,
    this.ownerId,
    this.amenities = const [],
    this.ratings,
    this.averageRating,
  });

  // Computed properties to match your service's GasStation class
  String get fuelTypesString {
    if (prices == null || prices!.isEmpty) return '';
    // Normalize fuel types to title case to avoid duplicates
    final normalizedTypes =
        prices!.keys.map((type) => _toTitleCase(type)).toList();
    return normalizedTypes.join(', ');
  }

  // Helper method to convert string to title case
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  // Get the reduced price for a specific fuel type
  double getReducedPrice(String fuelType) {
    final normalizedFuelType = fuelType.toLowerCase();
    final originalPrice = prices?[normalizedFuelType] ?? 0.0;
    final reduction = priceReductions?[normalizedFuelType] ?? 0.0;
    return originalPrice - reduction;
  }

  // Get the reduction amount for a specific fuel type
  double getReductionAmount(String fuelType) {
    final normalizedFuelType = fuelType.toLowerCase();
    return priceReductions?[normalizedFuelType] ?? 0.0;
  }

  // Check if there's a price reduction for a specific fuel type
  bool hasPriceReduction(String fuelType) {
    final normalizedFuelType = fuelType.toLowerCase();
    final reduction = priceReductions?[normalizedFuelType] ?? 0.0;
    return reduction > 0;
  }

  double get priceAsDouble {
    if (prices == null || prices!.isEmpty) return double.infinity;
    // Prefer 'Regular' if available, otherwise return the first available value
    if (prices!.containsKey('Regular') && prices!['Regular'] != null)
      return prices!['Regular']!;
    final firstValidPrice = prices!.values
        .firstWhere((price) => price != null, orElse: () => double.infinity);
    return firstValidPrice ?? double.infinity;
  }

  String get formattedRating =>
      (averageRating ?? rating ?? 0).toStringAsFixed(1);

  String getDistanceFrom(LatLng userLocation) {
    final distance = _calculateDistance(userLocation, position);
    return distance > 1
        ? '${distance.toStringAsFixed(1)} km'
        : '${(distance * 1000).toStringAsFixed(0)} m';
  }

  // Distance calculation using Haversine formula
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // kilometers

    double lat1 = point1.latitude * (pi / 180);
    double lat2 = point2.latitude * (pi / 180);
    double deltaLat = (point2.latitude - point1.latitude) * (pi / 180);
    double deltaLng = (point2.longitude - point1.longitude) * (pi / 180);

    double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) * sin(deltaLng / 2) * sin(deltaLng / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  // Optional: copyWith to support immutable-style updates
  GasStation copyWith({
    String? id,
    String? name,
    LatLng? position,
    String? brand,
    Map<String, double>? prices,
    double? rating,
    bool? isOpen,
    String? address,
    List<dynamic>? offers,
    List<dynamic>? vouchers,
    List<String>? services,
    bool? isOwnerCreated,
    String? ownerId,
    List<dynamic>? amenities,
    Map<String, dynamic>? ratings,
    double? averageRating,
  }) {
    return GasStation(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      brand: brand ?? this.brand,
      prices: prices ?? this.prices,
      rating: rating ?? this.rating,
      isOpen: isOpen ?? this.isOpen,
      address: address ?? this.address,
      offers: offers ?? this.offers,
      vouchers: vouchers ?? this.vouchers,
      services: services ?? this.services,
      isOwnerCreated: isOwnerCreated ?? this.isOwnerCreated,
      ownerId: ownerId ?? this.ownerId,
      amenities: amenities ?? this.amenities,
      ratings: ratings ?? this.ratings,
      averageRating: averageRating ?? this.averageRating,
    );
  }

  factory GasStation.fromMap(Map<String, dynamic> map) {
    // Parse position - check 'position', 'geoPoint', and 'location' fields
    LatLng position;
    var posRaw = map['position'];

    // If position is null, check for geoPoint
    if (posRaw == null) {
      posRaw = map['geoPoint'];
    }

    // If still null, check for location (used in some older documents)
    if (posRaw == null) {
      posRaw = map['location'];
    }

    if (posRaw is Map) {
      final lat = (posRaw['latitude'] ?? posRaw['lat'] ?? 0.0).toDouble();
      final lng = (posRaw['longitude'] ?? posRaw['lng'] ?? posRaw['lon'] ?? 0.0)
          .toDouble();
      position = LatLng(lat, lng);
    } else if (posRaw != null) {
      // Handle GeoPoint type directly (if passed from Firestore)
      try {
        final geo = posRaw as dynamic;
        if (geo.latitude != null && geo.longitude != null) {
          position = LatLng(geo.latitude.toDouble(), geo.longitude.toDouble());
        } else {
          position = const LatLng(0, 0);
        }
      } catch (e) {
        position = const LatLng(0, 0);
      }
    } else {
      position = const LatLng(0, 0);
    }

    return GasStation(
      id: map['id']?.toString(),
      name: map['name']?.toString(),
      position: position,
      brand: map['brand']?.toString(),
      prices: _normalizePrices(map['prices']),
      priceReductions: _normalizePrices(map['priceReductions']),
      fuelPerformance: _normalizePerformance(map['fuelPerformance']),
      rating: map['rating']?.toDouble(),
      isOpen: map['isOpen'] ?? true,
      address: map['address']?.toString(),
      offers: map['offers'] ?? [],
      vouchers: map['vouchers'] ?? [],
      services: map['services']?.cast<String>(),
      isOwnerCreated: map['isOwnerCreated'],
      ownerId: map['ownerId']?.toString(),
      amenities: List<dynamic>.from(map['amenities'] ?? []),
      ratings: map['ratings']?.cast<String, dynamic>(),
      averageRating: map['averageRating']?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'position': {
        'latitude': position.latitude,
        'longitude': position.longitude
      },
      'brand': brand,
      'prices': prices,
      'priceReductions': priceReductions,
      'fuelPerformance': fuelPerformance,
      'rating': rating,
      'isOpen': isOpen,
      'address': address,
      'offers': offers,
      'vouchers': vouchers,
      'services': services,
      'isOwnerCreated': isOwnerCreated,
      'ownerId': ownerId,
      'amenities': amenities,
      'ratings': ratings,
      'averageRating': averageRating,
    };
  }

  static Map<String, Map<String, dynamic>>? _normalizePerformance(
      dynamic performance) {
    if (performance == null) return null;
    if (performance is Map) {
      final normalized = <String, Map<String, dynamic>>{};
      performance.forEach((key, value) {
        if (value is Map) {
          normalized[key.toString()] = Map<String, dynamic>.from(value);
        }
      });
      return normalized;
    }
    return null;
  }

  static Map<String, double>? _normalizePrices(dynamic prices) {
    if (prices == null) return null;
    if (prices is Map<String, double>) return Map<String, double>.from(prices);
    if (prices is Map) {
      final normalized = <String, double>{};
      prices.forEach((key, value) {
        final normalizedKey = key.toString().trim().toLowerCase();
        if (normalizedKey.isEmpty) return;

        double? parsedValue;
        if (value is num) {
          parsedValue = value.toDouble();
        } else if (value != null) {
          parsedValue = double.tryParse(value.toString());
        }

        if (parsedValue == null) return;
        if (!parsedValue.isFinite || parsedValue.isNaN) return;
        if (parsedValue < 0) parsedValue = 0;

        normalized[normalizedKey] = parsedValue;
      });
      return normalized;
    }
    return null;
  }

  @override
  String toString() {
    return 'GasStation(id: $id, name: $name, brand: $brand, rating: $rating, avg: $averageRating)';
  }
}
