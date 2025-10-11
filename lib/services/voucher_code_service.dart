import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_service.dart';

class VoucherCodeService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final CollectionReference _gasStationsCollection = _db.collection('gas_stations');

  // Generate a unique voucher code
  static Future<String> generateUniqueVoucherCode({
    String? prefix,
    int length = 8,
  }) async {
    String code;
    bool isUnique = false;
    int attempts = 0;
    const maxAttempts = 10;

    do {
      code = _generateVoucherCode(prefix: prefix, length: length);
      isUnique = await _isCodeUnique(code);
      attempts++;
      
      if (attempts >= maxAttempts) {
        // If we can't find a unique code, append timestamp
        code = '${code}_${DateTime.now().millisecondsSinceEpoch}';
        break;
      }
    } while (!isUnique);

    return code;
  }

  // Generate a voucher code with optional prefix
  static String _generateVoucherCode({
    String? prefix,
    int length = 8,
  }) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    
    String code = '';
    
    // Add prefix if provided
    if (prefix != null && prefix.isNotEmpty) {
      code += prefix.toUpperCase();
    }
    
    // Generate random characters
    for (int i = 0; i < length; i++) {
      code += chars[random.nextInt(chars.length)];
    }
    
    return code;
  }

  // Check if a voucher code is unique across all stations
  static Future<bool> _isCodeUnique(String code) async {
    try {
      // Query all gas stations to check for existing voucher codes
      final querySnapshot = await _gasStationsCollection.get();
      
      for (final doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final vouchers = List<Map<String, dynamic>>.from(data['vouchers'] ?? []);
        
        for (final voucher in vouchers) {
          if (voucher['code']?.toString().toUpperCase() == code.toUpperCase()) {
            return false; // Code already exists
          }
        }
      }
      
      return true; // Code is unique
    } catch (e) {
      print('Error checking code uniqueness: $e');
      return true; // Assume unique if error occurs
    }
  }

  // Validate a voucher code at a specific station
  static Future<Map<String, dynamic>?> validateVoucherCode({
    required String code,
    required String stationId,
  }) async {
    try {
      final stationDoc = await _gasStationsCollection.doc(stationId).get();
      if (!stationDoc.exists) return null;

      final data = stationDoc.data() as Map<String, dynamic>;
      final vouchers = List<Map<String, dynamic>>.from(data['vouchers'] ?? []);

      for (final voucher in vouchers) {
        if (voucher['code']?.toString().toUpperCase() == code.toUpperCase()) {
          // Check if voucher is valid
          if (_isVoucherValid(voucher)) {
            return voucher;
          }
        }
      }

      return null; // Code not found or invalid
    } catch (e) {
      print('Error validating voucher code: $e');
      return null;
    }
  }

  // Check if a voucher is valid (not expired, active, etc.)
  static bool _isVoucherValid(Map<String, dynamic> voucher) {
    // Check status
    if (voucher['status'] != 'Active') return false;

    // Check expiry
    if (voucher['validUntil'] != null) {
      DateTime validUntil;
      if (voucher['validUntil'] is Timestamp) {
        validUntil = (voucher['validUntil'] as Timestamp).toDate();
      } else {
        validUntil = DateTime.parse(voucher['validUntil'].toString());
      }
      if (validUntil.isBefore(DateTime.now())) return false;
    }

    // Check usage limits
    final int? used = (voucher['used'] is num) ? (voucher['used'] as num).toInt() : null;
    final int? maxUses = (voucher['maxUses'] is num) ? (voucher['maxUses'] as num).toInt() : null;
    if (maxUses != null && used != null && used >= maxUses) return false;

    return true;
  }

  // Get suggested code prefixes based on station brand
  static String getSuggestedPrefix(String? brand) {
    if (brand == null || brand.isEmpty) return 'FUEL';
    
    switch (brand.toLowerCase()) {
      case 'shell':
        return 'SHL';
      case 'petron':
        return 'PTR';
      case 'caltex':
        return 'CTX';
      case 'total':
        return 'TOT';
      case 'unioil':
        return 'UNI';
      case 'phoenix':
        return 'PHX';
      default:
        return brand.substring(0, brand.length > 3 ? 3 : brand.length).toUpperCase();
    }
  }

  // Generate multiple unique codes for bulk operations
  static Future<List<String>> generateMultipleCodes({
    required int count,
    String? prefix,
    int length = 8,
  }) async {
    final List<String> codes = [];
    
    for (int i = 0; i < count; i++) {
      final code = await generateUniqueVoucherCode(
        prefix: prefix,
        length: length,
      );
      codes.add(code);
    }
    
    return codes;
  }
}
