import 'package:cloud_firestore/cloud_firestore.dart';

class PriceHistory {
  final String id;
  final String stationId;
  final String fuelType;
  final double price;
  final DateTime timestamp;
  final String stationName;
  final String stationBrand;

  PriceHistory({
    required this.id,
    required this.stationId,
    required this.fuelType,
    required this.price,
    required this.timestamp,
    required this.stationName,
    required this.stationBrand,
  });

  factory PriceHistory.fromMap(Map<String, dynamic> map, String id) {
    return PriceHistory(
      id: id,
      stationId: map['stationId'] ?? '',
      fuelType: map['fuelType'] ?? 'Regular',
      price: (map['price'] ?? 0.0).toDouble(),
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      stationName: map['stationName'] ?? 'Unknown Station',
      stationBrand: map['stationBrand'] ?? 'Unknown Brand',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'stationId': stationId,
      'fuelType': fuelType,
      'price': price,
      'timestamp': Timestamp.fromDate(timestamp),
      'stationName': stationName,
      'stationBrand': stationBrand,
    };
  }

  @override
  String toString() {
    return 'PriceHistory(id: $id, stationId: $stationId, fuelType: $fuelType, price: $price, timestamp: $timestamp)';
  }
}
