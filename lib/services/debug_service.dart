import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../models/gas_station.dart';
import '../services/gas_station_service.dart';
import 'firestore_service.dart';

class DebugService {
  static Future<void> debugGasStationVisibility() async {
    print('\n=== GAS STATION VISIBILITY DEBUG ===');

    try {
      // 1. Check Firestore data directly
      print('\n1. Checking Firestore data...');
      final firestoreStations = await FirestoreService.getAllGasStations();
      print('Found ${firestoreStations.length} stations in Firestore:');

      for (final station in firestoreStations) {
        print('  - ID: ${station['id']}');
        print('    Name: ${station['name']}');
        print('    Brand: ${station['brand']}');
        print('    Position: ${station['position']}');
        print('    Owner ID: ${station['ownerId']}');
        print('    Is Owner Created: ${station['isOwnerCreated']}');
        print('    Prices: ${station['prices']}');
        print('    Services: ${station['services']}');
        print('    Amenities: ${station['amenities']}');
        print('');
      }

      // 2. Check GasStationService cache
      print('\n2. Checking GasStationService cache...');
      GasStationService.clearCache();
      await GasStationService.fetchAndCacheGasStations();
      final cachedStations = GasStationService.getAllGasStations();
      print('Found ${cachedStations.length} stations in cache:');

      for (final station in cachedStations) {
        print('  - ID: ${station.id}');
        print('    Name: ${station.name}');
        print('    Brand: ${station.brand}');
        print('    Position: (${station.position.latitude}, ${station.position.longitude})');
        print('    Is Open: ${station.isOpen}');
        print('    Owner Created: ${station.isOwnerCreated}');
        print('');
      }

      // 3. Check for data structure issues
      print('\n3. Checking for data structure issues...');
      for (final station in firestoreStations) {
        final issues = <String>[];

        if (station['name'] == null || station['name'].toString().isEmpty) {
          issues.add('Missing name');
        }
        if (station['brand'] == null || station['brand'].toString().isEmpty) {
          issues.add('Missing brand');
        }
        if (station['position'] == null) {
          issues.add('Missing position');
        } else {
          final pos = station['position'];
          if (pos is Map) {
            final lat = pos['latitude'] ?? pos['lat'];
            final lng = pos['longitude'] ?? pos['lon'];
            if (lat == null || lng == null) {
              issues.add('Invalid position format');
            } else if (lat == 0.0 && lng == 0.0) {
              issues.add('Position is (0,0) - invalid coordinates');
            }
          } else if (pos is! GeoPoint) {
            issues.add('Position not in expected format');
          }
        }

        if (issues.isNotEmpty) {
          print('  Station ${station['id']} has issues: ${issues.join(', ')}');
        }
      }

      // 4. Test individual station parsing
      print('\n4. Testing individual station parsing...');
      for (final firestoreStation in firestoreStations) {
        try {
          final parsedStation = _parseStationData(firestoreStation);
          print('  ✓ Station ${firestoreStation['id']} parsed successfully');
        } catch (e) {
          print('  ✗ Station ${firestoreStation['id']} failed to parse: $e');
        }
      }

    } catch (e) {
      print('Error during debug: $e');
    }

    print('\n=== DEBUG COMPLETE ===\n');
  }

  static GasStation _parseStationData(Map<String, dynamic> stationData) {
    // Parse position
    double lat = 0.0;
    double lng = 0.0;

    final posRaw = stationData['position'];
    if (posRaw is GeoPoint) {
      lat = posRaw.latitude;
      lng = posRaw.longitude;
    } else if (posRaw is Map) {
      lat = (posRaw['latitude'] ?? posRaw['lat'] ?? 0.0).toDouble();
      lng = (posRaw['longitude'] ?? posRaw['lon'] ?? 0.0).toDouble();
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

    return GasStation(
      id: stationData['id']?.toString(),
      name: stationData['name']?.toString(),
      position: LatLng(lat, lng),
      brand: stationData['brand']?.toString(),
      address: stationData['address']?.toString(),
      prices: prices,
      services: List<String>.from(stationData['services'] ?? []),
      rating: (stationData['rating'] ?? 0.0).toDouble(),
      isOpen: stationData['isOpen'] ?? true,
      offers: stationData['offers'] ?? [],
      vouchers: stationData['vouchers'] ?? [],
      isOwnerCreated: stationData['isOwnerCreated'] ?? false,
      ownerId: stationData['ownerId']?.toString(),
      amenities: List<dynamic>.from(stationData['amenities'] ?? []),
    );
  }

  static Future<void> forceRefreshStations() async {
    print('Forcing refresh of gas stations...');
    GasStationService.clearCache();
    await GasStationService.fetchAndCacheGasStations();
    print('Refresh complete');
  }
}
