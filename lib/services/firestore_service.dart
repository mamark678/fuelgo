import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../models/price_history.dart';

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Collection references
  static CollectionReference get gasStationsCollection => _db.collection('gas_stations');
  static CollectionReference get usersCollection => _db.collection('users');
  // Create or update gas station data
  static Future<void> createOrUpdateGasStation({
    required String stationId,
    required String name,
    required String brand,
    required LatLng position,
    required String address,
    required Map<String, double> prices,
    required String ownerId,
    String? stationName,
  }) async {
    try {
      await gasStationsCollection.doc(stationId).set({
        'name': name,
        'brand': brand,
        'position': {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        'address': address,
        'prices': prices,
        'ownerId': ownerId,
        'stationName': stationName ?? name,
        'rating': 0.0,
        'isOpen': true,
        'services': [], // Keep for backward compatibility
        'amenities': [], // Add amenities field for consistency
        'offers': [],
        'vouchers': [],
        'isOwnerCreated': true, // Mark as owner-created
        'lastUpdated': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to create/update gas station: $e');
    }
  }

  // Offers management methods

  // Get all offers for all stations owned by a user
  static Future<List<Map<String, dynamic>>> getOffersByOwner(String ownerId) async {
    try {
      final stations = await getGasStationsByOwner(ownerId);
      final List<Map<String, dynamic>> offers = [];
      for (final station in stations) {
        final stationOffers = List<Map<String, dynamic>>.from(station['offers'] ?? []);
        for (final offer in stationOffers) {
          final offerWithStation = Map<String, dynamic>.from(offer);
          offerWithStation['stationId'] = station['id'];
          offers.add(offerWithStation);
        }
      }
      return offers;
    } catch (e) {
      throw Exception('Failed to get offers by owner: $e');
    }
  }

  // Add an offer to a gas station
  static Future<void> addOffer({
    required String stationId,
    required Map<String, dynamic> offer,
  }) async {
    try {
      // Validate stationId is not empty
      if (stationId.isEmpty) {
        throw Exception('Station ID cannot be empty when adding an offer');
      }
      
      await gasStationsCollection.doc(stationId).update({
        'offers': FieldValue.arrayUnion([offer]),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to add offer: $e');
    }
  }

  // Update an offer in a gas station
  static Future<void> updateOffer({
    required String stationId,
    required Map<String, dynamic> oldOffer,
    required Map<String, dynamic> newOffer,
  }) async {
    try {
      // Validate stationId is not empty
      if (stationId.isEmpty) {
        throw Exception('Station ID cannot be empty when updating an offer');
      }
      
      final docRef = gasStationsCollection.doc(stationId);
      final doc = await docRef.get();
      if (!doc.exists) throw Exception('Gas station not found');

      final data = doc.data() as Map<String, dynamic>;
      final offers = List<Map<String, dynamic>>.from(data['offers'] ?? []);

      final index = offers.indexWhere((o) => o['id'] == oldOffer['id']);
      if (index == -1) throw Exception('Offer not found');

      offers[index] = newOffer;

      await docRef.update({
        'offers': offers,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update offer: $e');
    }
  }

  // Delete an offer from a gas station
  static Future<void> deleteOffer({
    required String stationId,
    required Map<String, dynamic> offer,
  }) async {
    try {
      // Validate stationId is not empty
      if (stationId.isEmpty) {
        throw Exception('Station ID cannot be empty when deleting an offer');
      }
      
      await gasStationsCollection.doc(stationId).update({
        'offers': FieldValue.arrayRemove([offer]),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to delete offer: $e');
    }
  }

  // Claim/Redemption methods

  // Claim an offer for a user
  static Future<void> claimOffer({
    required String stationId,
    required String offerId,
    required String userId,
    required String userName,
  }) async {
    try {
      // Validate stationId is not empty
      if (stationId.isEmpty) {
        throw Exception('Station ID cannot be empty when claiming an offer');
      }
      
      final docRef = gasStationsCollection.doc(stationId);
      final doc = await docRef.get();
      if (!doc.exists) throw Exception('Gas station not found');

      final data = doc.data() as Map<String, dynamic>;
      final offers = List<Map<String, dynamic>>.from(data['offers'] ?? []);

      final offerIndex = offers.indexWhere((o) => o['id'] == offerId);
      if (offerIndex == -1) throw Exception('Offer not found');

      final offer = offers[offerIndex];
      
      // Check if offer is active
      final status = offer['status'] ?? 'Active';
      if (status != 'Active') {
        throw Exception('Offer is not active');
      }
      
      // Check expiry date
      if (offer['validUntil'] != null) {
        DateTime validUntil;
        if (offer['validUntil'] is Timestamp) {
          validUntil = (offer['validUntil'] as Timestamp).toDate();
        } else {
          validUntil = DateTime.parse(offer['validUntil'].toString());
        }
        if (validUntil.isBefore(DateTime.now())) {
          throw Exception('Offer has expired');
        }
      }
      
      final currentUsed = ((offer['used'] ?? 0) as num).toInt();
      final maxUses = ((offer['maxUses'] ?? 0) as num).toInt();

      // If maxUses is 0, it means unlimited uses
      if (maxUses > 0 && currentUsed >= maxUses) {
        throw Exception('Offer has reached maximum claims');
      }

      // Check if user has already claimed this offer
      final userClaimedQuery = await usersCollection
          .doc(userId)
          .collection('claimed_offers')
          .where('offerId', isEqualTo: offerId)
          .get();
      
      if (userClaimedQuery.docs.isNotEmpty) {
        throw Exception('You have already claimed this offer');
      }

      // Update offer usage
      offers[offerIndex] = {
        ...offer,
        'used': currentUsed + 1,
      };

      // Record the claim in user's collection
      await usersCollection.doc(userId).collection('claimed_offers').add({
        'offerId': offerId,
        'stationId': stationId,
        'stationName': data['name'] ?? '',
        'offerTitle': offer['title'] ?? '',
        'userId': userId,
        'userName': userName,
        'claimedAt': FieldValue.serverTimestamp(),
        'status': 'claimed',
      });

      // Update the station's offers
      await docRef.update({
        'offers': offers,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

    } catch (e) {
      throw Exception('Failed to claim offer: $e');
    }
  }

  // Get user's claimed offers
  static Future<List<Map<String, dynamic>>> getUserClaimedOffers(String userId) async {
    try {
      final querySnapshot = await usersCollection
          .doc(userId)
          .collection('claimed_offers')
          .orderBy('claimedAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Failed to get user claimed offers: $e');
    }
  }

  // Get user's redeemed vouchers
  static Future<List<Map<String, dynamic>>> getUserRedeemedVouchers(String userId) async {
    try {
      final querySnapshot = await usersCollection
          .doc(userId)
          .collection('redeemed_vouchers')
          .orderBy('redeemedAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Failed to get user redeemed vouchers: $e');
    }
  }

  // Search vouchers across all stations
  static Future<List<Map<String, dynamic>>> searchVouchers({
    String? query,
    String? status,
    String? voucherType,
    int limit = 50,
  }) async {
    try {
      final allStations = await getAllGasStations();
      final List<Map<String, dynamic>> matchingVouchers = [];

      for (final station in allStations) {
        final stationVouchers = List<Map<String, dynamic>>.from(station['vouchers'] ?? []);
        
        for (final voucher in stationVouchers) {
          // Apply filters
          bool matches = true;

          // Status filter
          if (status != null && status != 'All') {
            final voucherStatus = voucher['status'] ?? 'Active';
            if (voucherStatus != status) {
              matches = false;
            }
          }

          // Voucher type filter
          if (voucherType != null && voucherType != 'All') {
            final discountType = voucher['discountType'] ?? '';
            
            if (voucherType == 'Percentage' && discountType != 'percentage') {
              matches = false;
            } else if (voucherType == 'Fixed Amount' && discountType != 'fixed_amount') {
              matches = false;
            } else if (voucherType == 'Free Item' && discountType != 'free_item') {
              matches = false;
            }
          }

          // Search query filter
          if (query != null && query.isNotEmpty) {
            final title = (voucher['title'] ?? '').toString().toLowerCase();
            final description = (voucher['description'] ?? '').toString().toLowerCase();
            final stationName = (station['name'] ?? '').toString().toLowerCase();
            
            if (!title.contains(query.toLowerCase()) &&
                !description.contains(query.toLowerCase()) &&
                !stationName.contains(query.toLowerCase())) {
              matches = false;
            }
          }

          if (matches) {
            final voucherWithStation = Map<String, dynamic>.from(voucher);
            voucherWithStation['stationId'] = station['id'];
            voucherWithStation['stationName'] = station['name'] ?? '';
            voucherWithStation['stationBrand'] = station['brand'] ?? '';
            matchingVouchers.add(voucherWithStation);
          }

          if (matchingVouchers.length >= limit) break;
        }
        
        if (matchingVouchers.length >= limit) break;
      }

      return matchingVouchers;
    } catch (e) {
      throw Exception('Failed to search vouchers: $e');
    }
  }

  // Search offers across all stations
  static Future<List<Map<String, dynamic>>> searchOffers({
    String? query,
    String? status,
    String? offerType,
    int limit = 50,
  }) async {
    try {
      final allStations = await getAllGasStations();
      final List<Map<String, dynamic>> matchingOffers = [];

      for (final station in allStations) {
        final stationOffers = List<Map<String, dynamic>>.from(station['offers'] ?? []);
        
        for (final offer in stationOffers) {
          // Apply filters
          bool matches = true;

          // Status filter
          if (status != null && status != 'All') {
            final offerStatus = offer['status'] ?? 'Active';
            if (offerStatus != status) {
              matches = false;
            }
          }

          // Offer type filter
          if (offerType != null && offerType != 'All') {
            final hasDiscount = offer['discount'] != null;
            final hasCashback = offer['cashback'] != null;
            
            if (offerType == 'Discount' && !hasDiscount) {
              matches = false;
            } else if (offerType == 'Cashback' && !hasCashback) {
              matches = false;
            } else if (offerType == 'Special' && (hasDiscount || hasCashback)) {
              matches = false;
            }
          }

          // Search query filter
          if (query != null && query.isNotEmpty) {
            final title = (offer['title'] ?? '').toString().toLowerCase();
            final description = (offer['description'] ?? '').toString().toLowerCase();
            final stationName = (station['name'] ?? '').toString().toLowerCase();
            
            if (!title.contains(query.toLowerCase()) &&
                !description.contains(query.toLowerCase()) &&
                !stationName.contains(query.toLowerCase())) {
              matches = false;
            }
          }

          if (matches) {
            final offerWithStation = Map<String, dynamic>.from(offer);
            offerWithStation['stationId'] = station['id'];
            offerWithStation['stationName'] = station['name'] ?? '';
            offerWithStation['stationBrand'] = station['brand'] ?? '';
            matchingOffers.add(offerWithStation);
          }

          if (matchingOffers.length >= limit) break;
        }
        
        if (matchingOffers.length >= limit) break;
      }

      return matchingOffers;
    } catch (e) {
      throw Exception('Failed to search offers: $e');
    }
  }

  // Voucher management methods

  // Get all vouchers for all stations owned by a user
  static Future<List<Map<String, dynamic>>> getVouchersByOwner(String ownerId) async {
    try {
      final stations = await getGasStationsByOwner(ownerId);
      final List<Map<String, dynamic>> vouchers = [];
      for (final station in stations) {
        final stationVouchers = List<Map<String, dynamic>>.from(station['vouchers'] ?? []);
        for (final voucher in stationVouchers) {
          final voucherWithStation = Map<String, dynamic>.from(voucher);
          voucherWithStation['stationId'] = station['id'];
          vouchers.add(voucherWithStation);
        }
      }
      return vouchers;
    } catch (e) {
      throw Exception('Failed to get vouchers by owner: $e');
    }
  }

  // Add a voucher to a gas station
  static Future<void> addVoucher({
    required String stationId,
    required Map<String, dynamic> voucher,
  }) async {
    try {
      if (stationId.isEmpty) {
        throw Exception('Station ID cannot be empty when adding a voucher');
      }
      
      await gasStationsCollection.doc(stationId).update({
        'vouchers': FieldValue.arrayUnion([voucher]),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to add voucher: $e');
    }
  }

  // Update a voucher in a gas station
  static Future<void> updateVoucher({
    required String stationId,
    required Map<String, dynamic> oldVoucher,
    required Map<String, dynamic> newVoucher,
  }) async {
    try {
      if (stationId.isEmpty) {
        throw Exception('Station ID cannot be empty when updating a voucher');
      }
      
      final docRef = gasStationsCollection.doc(stationId);
      final doc = await docRef.get();
      if (!doc.exists) throw Exception('Gas station not found');

      final data = doc.data() as Map<String, dynamic>;
      final vouchers = List<Map<String, dynamic>>.from(data['vouchers'] ?? []);

      final index = vouchers.indexWhere((v) => v['id'] == oldVoucher['id']);
      if (index == -1) throw Exception('Voucher not found');

      vouchers[index] = newVoucher;

      await docRef.update({
        'vouchers': vouchers,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update voucher: $e');
    }
  }

  // Delete a voucher from a gas station
  static Future<void> deleteVoucher({
    required String stationId,
    required Map<String, dynamic> voucher,
  }) async {
    try {
      if (stationId.isEmpty) {
        throw Exception('Station ID cannot be empty when deleting a voucher');
      }
      
      await gasStationsCollection.doc(stationId).update({
        'vouchers': FieldValue.arrayRemove([voucher]),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to delete voucher: $e');
    }
  }

  // Redeem a voucher for a user (vouchers are stored in gas_stations collection)
 // Redeem a voucher for a user (store redemption as station subdoc + user history)
static Future<void> redeemVoucher({
  required String voucherId,
  required String stationId,
  required String userId,
  required String userName,
}) async {
  if (stationId.isEmpty) throw Exception('Station ID cannot be empty when redeeming a voucher');

  final stationRef = gasStationsCollection.doc(stationId);
  final stationRedemptionRef = stationRef.collection('vouchers_redemptions').doc(userId);
  final userRedeemedRef = usersCollection.doc(userId).collection('redeemed_vouchers').doc();

  try {
    await _db.runTransaction((tx) async {
      final stationSnap = await tx.get(stationRef);
      if (!stationSnap.exists) throw Exception('Gas station not found');

      final stationData = stationSnap.data() as Map<String, dynamic>;
      final vouchers = List<Map<String, dynamic>>.from(stationData['vouchers'] ?? []);
      final voucherIndex = vouchers.indexWhere((v) => v['id'] == voucherId);
      if (voucherIndex == -1) throw Exception('Voucher not found');

      final voucher = vouchers[voucherIndex];

      // Expiry check
      if (voucher['validUntil'] != null) {
        DateTime validUntil;
        if (voucher['validUntil'] is Timestamp) {
          validUntil = (voucher['validUntil'] as Timestamp).toDate();
        } else {
          validUntil = DateTime.parse(voucher['validUntil'].toString());
        }
        if (validUntil.isBefore(DateTime.now())) throw Exception('Voucher expired');
      }

      // Quantity / max uses check
      final int? quantity = (voucher['quantity'] is num) ? (voucher['quantity'] as num).toInt() : null;
      final int? used = (voucher['used'] is num) ? (voucher['used'] as num).toInt() : null;
      final int? maxUses = (voucher['maxUses'] is num) ? (voucher['maxUses'] as num).toInt() : null;
      if (quantity != null && quantity <= 0) throw Exception('Voucher out of stock');
      if (maxUses != null && used != null && used >= maxUses) throw Exception('Voucher has reached maximum redemptions');

      // Ensure user hasn't already redeemed this voucher (under station)
      final existingStationRedemption = await tx.get(stationRedemptionRef);
      if (existingStationRedemption.exists) throw Exception('You have already redeemed this voucher');

      // Create redemption doc under station subcollection (id = userId)
      tx.set(stationRedemptionRef, {
        'voucherId': voucherId,
        'stationId': stationId,
        'userId': userId,
        'userName': userName,
        'voucherCode': voucher['code'] ?? '',
        'claimedAt': FieldValue.serverTimestamp(),
      });

      // Add to user's redeemed_vouchers (history)
      tx.set(userRedeemedRef, {
        'voucherId': voucherId,
        'stationId': stationId,
        'voucherTitle': voucher['title'] ?? '',
        'voucherCode': voucher['code'] ?? '',
        'userId': userId,
        'userName': userName,
        'redeemedAt': FieldValue.serverTimestamp(),
        'status': 'redeemed',
      });

      // Calculate and store price reduction based on voucher
      await _calculateAndStorePriceReduction(tx, stationRef, voucher, stationData);
    });
  } catch (e) {
    throw Exception('Failed to redeem voucher: $e');
  }
}

  // Helper method to calculate and store price reduction based on voucher redemption
  static Future<void> _calculateAndStorePriceReduction(
    Transaction tx,
    DocumentReference stationRef,
    Map<String, dynamic> voucher,
    Map<String, dynamic> stationData,
  ) async {
    try {
      final currentPrices = Map<String, double>.from(stationData['prices'] ?? {});
      final applicableFuelTypes = List<String>.from(voucher['applicableFuelTypes'] ?? ['Regular', 'Premium', 'Diesel']);
      final discountType = voucher['discountType'] ?? 'percentage';
      final discountValue = (voucher['discountValue'] ?? 0.0).toDouble();
      
      // Get existing price reductions or initialize empty map
      final existingReductions = Map<String, double>.from(stationData['priceReductions'] ?? {});
      final updatedReductions = Map<String, double>.from(existingReductions);
      
      // Calculate price reduction for each applicable fuel type
      for (final fuelType in applicableFuelTypes) {
        final normalizedFuelType = fuelType.toLowerCase();
        final currentPrice = currentPrices[normalizedFuelType] ?? 0.0;
        
        if (currentPrice > 0) {
          double reductionAmount = 0.0;
          
          if (discountType == 'percentage' && discountValue > 0) {
            reductionAmount = currentPrice * (discountValue / 100);
          } else if (discountType == 'fixed_amount' && discountValue > 0) {
            reductionAmount = discountValue;
          }
          
          // Add to existing reduction (cumulative)
          final existingReduction = updatedReductions[normalizedFuelType] ?? 0.0;
          updatedReductions[normalizedFuelType] = existingReduction + reductionAmount;
        }
      }
      
      // Update station document with price reductions
      tx.update(stationRef, {
        'priceReductions': updatedReductions,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      
      // Record price reduction history for analytics
      final reductionHistoryRef = stationRef.collection('price_reduction_history').doc();
      tx.set(reductionHistoryRef, {
        'voucherId': voucher['id'],
        'voucherTitle': voucher['title'],
        'discountType': discountType,
        'discountValue': discountValue,
        'applicableFuelTypes': applicableFuelTypes,
        'reductionsApplied': updatedReductions,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
    } catch (e) {
      print('Error calculating price reduction: $e');
      // Don't throw error here to avoid breaking the main redemption flow
    }
  }

  // Get price reductions for a specific station
  static Future<Map<String, double>> getStationPriceReductions(String stationId) async {
    try {
      final doc = await gasStationsCollection.doc(stationId).get();
      if (!doc.exists) return {};
      
      final data = doc.data() as Map<String, dynamic>;
      return Map<String, double>.from(data['priceReductions'] ?? {});
    } catch (e) {
      print('Error getting price reductions: $e');
      return {};
    }
  }

  // Use/apply a voucher code at a gas station (for station staff)
  static Future<Map<String, dynamic>> useVoucherCode({
    required String code,
    required String stationId,
    required String userId,
    required String userName,
  }) async {
    try {
      // First validate the code
      final voucher = await _validateVoucherCodeForStation(code, stationId);
      if (voucher == null) {
        throw Exception('Invalid or expired voucher code');
      }

      // Check if user has already redeemed this voucher
      final stationRef = gasStationsCollection.doc(stationId);
      final userRedemptionRef = stationRef.collection('vouchers_redemptions').doc(userId);
      final existingRedemption = await userRedemptionRef.get();
      
      if (existingRedemption.exists) {
        throw Exception('You have already redeemed this voucher');
      }

      // Record the usage
      await userRedemptionRef.set({
        'voucherId': voucher['id'],
        'stationId': stationId,
        'userId': userId,
        'userName': userName,
        'voucherCode': code,
        'usedAt': FieldValue.serverTimestamp(),
        'status': 'used',
      });

      // Update voucher usage count
      await _updateVoucherUsageCount(stationId, voucher['id']);

      return {
        'success': true,
        'voucher': voucher,
        'message': 'Voucher used successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Failed to use voucher: $e',
      };
    }
  }

  // Helper method to validate voucher code for a specific station
  static Future<Map<String, dynamic>?> _validateVoucherCodeForStation(
    String code,
    String stationId,
  ) async {
    try {
      final stationDoc = await gasStationsCollection.doc(stationId).get();
      if (!stationDoc.exists) return null;

      final data = stationDoc.data() as Map<String, dynamic>;
      final vouchers = List<Map<String, dynamic>>.from(data['vouchers'] ?? []);

      for (final voucher in vouchers) {
        if (voucher['code']?.toString().toUpperCase() == code.toUpperCase()) {
          // Check if voucher is valid
          if (_isVoucherValidForUse(voucher)) {
            return voucher;
          }
        }
      }

      return null;
    } catch (e) {
      print('Error validating voucher code: $e');
      return null;
    }
  }

  // Check if a voucher is valid for use
  static bool _isVoucherValidForUse(Map<String, dynamic> voucher) {
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

  // Update voucher usage count
  static Future<void> _updateVoucherUsageCount(String stationId, String voucherId) async {
    try {
      final stationRef = gasStationsCollection.doc(stationId);
      final stationDoc = await stationRef.get();
      
      if (!stationDoc.exists) return;

      final data = stationDoc.data() as Map<String, dynamic>;
      final vouchers = List<Map<String, dynamic>>.from(data['vouchers'] ?? []);

      final voucherIndex = vouchers.indexWhere((v) => v['id'] == voucherId);
      if (voucherIndex != -1) {
        final currentUsed = (vouchers[voucherIndex]['used'] ?? 0) as int;
        vouchers[voucherIndex]['used'] = currentUsed + 1;

        await stationRef.update({
          'vouchers': vouchers,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error updating voucher usage count: $e');
    }
  }

  // Get offer analytics for a station owner
  static Future<Map<String, dynamic>> getOfferAnalytics(String ownerId) async {
    try {
      final stations = await getGasStationsByOwner(ownerId);
      int totalOffers = 0;
      int activeOffers = 0;
      int pausedOffers = 0;
      int expiredOffers = 0;
      int totalClaims = 0;
      int todayClaims = 0;
      final Map<String, int> claimsByOffer = {};
      final Map<String, int> claimsByDay = {};

      for (final station in stations) {
        final offers = List<Map<String, dynamic>>.from(station['offers'] ?? []);
        totalOffers += offers.length;

        for (final offer in offers) {
          final status = offer['status'] ?? 'Active';
          final used = ((offer['used'] ?? 0) as num).toInt();
          final offerId = offer['id'] ?? '';
          final createdAt = offer['createdAt'] != null 
              ? DateTime.parse(offer['createdAt'])
              : DateTime.now();
          final dayKey = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
          
          if (status == 'Active') {
            activeOffers++;
          } else if (status == 'Paused') {
            pausedOffers++;
          } else if (status == 'Expired') {
            expiredOffers++;
          }
          
          totalClaims += used;
          claimsByOffer[offerId] = used;
          claimsByDay[dayKey] = (claimsByDay[dayKey] ?? 0) + used;
        }
      }

      // Calculate today's claims
      final today = DateTime.now();
      final todayKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      todayClaims = claimsByDay[todayKey] ?? 0;

      return {
        'totalOffers': totalOffers,
        'activeOffers': activeOffers,
        'pausedOffers': pausedOffers,
        'expiredOffers': expiredOffers,
        'totalClaims': totalClaims,
        'todayClaims': todayClaims,
        'revenueImpact': totalClaims * 50.0,
        'claimsByOffer': claimsByOffer,
        'claimsByDay': claimsByDay,
        'averageClaimRate': totalOffers > 0 ? totalClaims / totalOffers : 0.0,
        'totalViews': totalClaims * 3, // Estimate views as 3x claims
        'uniqueUsers': (totalClaims * 0.7).round(), // Estimate unique users
      };
    } catch (e) {
      throw Exception('Failed to get offer analytics: $e');
    }
  }

  // Get voucher analytics for a station owner
  static Future<Map<String, dynamic>> getVoucherAnalytics(String ownerId) async {
    try {
      final stations = await getGasStationsByOwner(ownerId);
      int totalVouchers = 0;
      int activeVouchers = 0;
      int pausedVouchers = 0;
      int expiredVouchers = 0;
      int totalRedemptions = 0;
      int todayRedemptions = 0;
      final Map<String, int> redemptionsByVoucher = {};
      final Map<String, int> redemptionsByDay = {};

      for (final station in stations) {
        final vouchers = List<Map<String, dynamic>>.from(station['vouchers'] ?? []);
        totalVouchers += vouchers.length;

        for (final voucher in vouchers) {
          final status = voucher['status'] ?? 'Active';
          final used = ((voucher['used'] ?? 0) as num).toInt();
          final voucherId = voucher['id'] ?? '';
          final createdAt = voucher['createdAt'] != null 
              ? DateTime.parse(voucher['createdAt'])
              : DateTime.now();
          final dayKey = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
          
          if (status == 'Active') {
            activeVouchers++;
          } else if (status == 'Paused') {
            pausedVouchers++;
          } else if (status == 'Expired') {
            expiredVouchers++;
          }
          
          totalRedemptions += used;
          redemptionsByVoucher[voucherId] = used;
          redemptionsByDay[dayKey] = (redemptionsByDay[dayKey] ?? 0) + used;
        }
      }

      // Calculate today's redemptions
      final today = DateTime.now();
      final todayKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      todayRedemptions = redemptionsByDay[todayKey] ?? 0;

      return {
        'totalVouchers': totalVouchers,
        'activeVouchers': activeVouchers,
        'pausedVouchers': pausedVouchers,
        'expiredVouchers': expiredVouchers,
        'totalRedemptions': totalRedemptions,
        'todayRedemptions': todayRedemptions,
        'revenueImpact': totalRedemptions * 30.0,
        'redemptionsByVoucher': redemptionsByVoucher,
        'redemptionsByDay': redemptionsByDay,
        'averageRedemptionRate': totalVouchers > 0 ? totalRedemptions / totalVouchers : 0.0,
        'totalViews': totalRedemptions * 2, // Estimate views as 2x redemptions
        'uniqueUsers': (totalRedemptions * 0.6).round(), // Estimate unique users
      };
    } catch (e) {
      throw Exception('Failed to get voucher analytics: $e');
    }
  }

  // Get combined analytics for offers and vouchers
  static Future<Map<String, dynamic>> getCombinedAnalytics(String ownerId) async {
    try {
      final offerAnalytics = await getOfferAnalytics(ownerId);
      final voucherAnalytics = await getVoucherAnalytics(ownerId);
      
      final totalRevenueImpact = (offerAnalytics['revenueImpact'] as double) + 
                                (voucherAnalytics['revenueImpact'] as double);
      final totalEngagement = (offerAnalytics['totalClaims'] as int) + 
                             (voucherAnalytics['totalRedemptions'] as int);
      final conversionRate = totalEngagement > 0 ? 
          (offerAnalytics['totalViews'] as int) + (voucherAnalytics['totalViews'] as int) / totalEngagement : 0.0;

      return {
        'offerAnalytics': offerAnalytics,
        'voucherAnalytics': voucherAnalytics,
        'totalRevenueImpact': totalRevenueImpact,
        'totalEngagement': totalEngagement,
        'conversionRate': conversionRate,
      };
    } catch (e) {
      throw Exception('Failed to get combined analytics: $e');
    }
  }

  // Get gas station by ID
  static Future<Map<String, dynamic>?> getGasStation(String stationId) async {
    try {
      final doc = await gasStationsCollection.doc(stationId).get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      // Handle permission errors gracefully
      if (e.toString().contains('PERMISSION_DENIED') || e.toString().contains('Missing or insufficient permissions')) {
        print('Permission denied accessing gas station: $stationId');
        return null;
      }
      throw Exception('Failed to get gas station: $e');
    }
  }

  // Get all gas stations
  static Future<List<Map<String, dynamic>>> getAllGasStations() async {
    try {
      print('[DEBUG] FirestoreService.getAllGasStations: Starting query...');
      final querySnapshot = await gasStationsCollection.get();
      print('[DEBUG] FirestoreService.getAllGasStations: Query completed. Found ${querySnapshot.docs.length} documents');

      if (querySnapshot.docs.isEmpty) {
        print('[DEBUG] FirestoreService.getAllGasStations: No documents found in gas_stations collection');
        print('[DEBUG] FirestoreService.getAllGasStations: This might indicate:');
        print('[DEBUG] FirestoreService.getAllGasStations: 1. Collection is empty');
        print('[DEBUG] FirestoreService.getAllGasStations: 2. Permission denied (check firestore.rules)');
        print('[DEBUG] FirestoreService.getAllGasStations: 3. Network connectivity issues');
      }

      final stations = querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;

        print('[DEBUG] FirestoreService.getAllGasStations: Processing station ${doc.id}');
        print('[DEBUG] FirestoreService.getAllGasStations: Raw data keys: ${data.keys.toList()}');
        print('[DEBUG] FirestoreService.getAllGasStations: Has ownerId: ${data.containsKey('ownerId')}');
        print('[DEBUG] FirestoreService.getAllGasStations: ownerId value: ${data['ownerId']}');

        // Handle GeoPoint -> Map
        if (data['position'] is GeoPoint) {
          final geo = data['position'] as GeoPoint;
          data['position'] = {'latitude': geo.latitude, 'longitude': geo.longitude};
          print('[DEBUG] FirestoreService.getAllGasStations: Converted GeoPoint to Map for station ${doc.id}');
        }

        // Ensure prices is Map<String, double>
        if (data['prices'] != null) {
          data['prices'] = Map<String, double>.from(
            (data['prices'] as Map).map((k, v) => MapEntry(k, (v as num).toDouble()))
          );
          print('[DEBUG] FirestoreService.getAllGasStations: Processed prices for station ${doc.id}: ${data['prices']}');
        } else {
          data['prices'] = {};
          print('[DEBUG] FirestoreService.getAllGasStations: No prices found for station ${doc.id}');
        }

        // Ensure amenities and services are synchronized
        if (data.containsKey('services') && !data.containsKey('amenities')) {
          data['amenities'] = data['services'];
        } else if (data.containsKey('amenities') && !data.containsKey('services')) {
          data['services'] = data['amenities'];
        }

        return data;
      }).toList();

      print('[DEBUG] FirestoreService.getAllGasStations: Successfully processed ${stations.length} stations');
      return stations;
    } catch (e) {
      print('[ERROR] FirestoreService.getAllGasStations: Failed to get all gas stations: $e');
      print('[ERROR] FirestoreService.getAllGasStations: Error type: ${e.runtimeType}');
      if (e.toString().contains('PERMISSION_DENIED')) {
        print('[ERROR] FirestoreService.getAllGasStations: Permission denied - check firestore.rules');
      }
      throw Exception('Failed to get all gas stations: $e');
    }
  }

  // Get gas stations by owner
  static Future<List<Map<String, dynamic>>> getGasStationsByOwner(String ownerId) async {
    try {
      final querySnapshot = await gasStationsCollection
          .where('ownerId', isEqualTo: ownerId)
          .get();
      return querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      // Handle permission errors gracefully
      if (e.toString().contains('PERMISSION_DENIED') || e.toString().contains('Missing or insufficient permissions')) {
        print('Permission denied accessing gas stations for owner: $ownerId');
        return [];
      }
      throw Exception('Failed to get gas stations by owner: $e');
    }
  }

  // Update gas station prices and performance
  static Future<void> updateGasStationPricesAndPerformance({
    required String stationId,
    required Map<String, double> prices,
    required Map<String, dynamic> fuelPerformance,
  }) async {
    try {
      await gasStationsCollection.doc(stationId).update({
        'prices': prices,
        'fuelPerformance': fuelPerformance,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update gas station prices and performance: $e');
    }
  }

  // Update gas station rating
  static Future<void> updateGasStationRating({
    required String stationId,
    required double rating,
  }) async {
    try {
      await gasStationsCollection.doc(stationId).update({
        'rating': rating,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update gas station rating: $e');
    }
  }

  // Update gas station amenities (services)
  static Future<void> updateGasStationAmenities({
    required String stationId,
    required List<Map<String, dynamic>> amenities,
  }) async {
    try {
      await gasStationsCollection.doc(stationId).update({
        'services': amenities, // Keep for backward compatibility
        'amenities': amenities, // Update amenities field
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update gas station amenities: $e');
    }
  }

  // Add a single amenity to gas station
  static Future<void> addAmenity({
    required String stationId,
    required String amenity,
  }) async {
    try {
      await gasStationsCollection.doc(stationId).update({
        'services': FieldValue.arrayUnion([amenity]), // Keep for backward compatibility
        'amenities': FieldValue.arrayUnion([amenity]), // Update amenities field
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to add amenity: $e');
    }
  }

  // Remove a single amenity from gas station
  static Future<void> removeAmenity({
    required String stationId,
    required String amenity,
  }) async {
    try {
      await gasStationsCollection.doc(stationId).update({
        'services': FieldValue.arrayRemove([amenity]), // Keep for backward compatibility
        'amenities': FieldValue.arrayRemove([amenity]), // Update amenities field
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to remove amenity: $e');
    }
  }

  // Get gas station amenities
  static Future<List<Map<String, dynamic>>> getGasStationAmenities(String stationId) async {
    try {
      final doc = await gasStationsCollection.doc(stationId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        // Use amenities field, fallback to services for backward compatibility
        return List<Map<String, dynamic>>.from(data['amenities'] ?? data['services'] ?? []);
      }
      return [];
    } catch (e) {
      throw Exception('Failed to get gas station amenities: $e');
    }
  }

  // Delete gas station
  static Future<void> deleteGasStation(String stationId) async {
    try {
      await gasStationsCollection.doc(stationId).delete();
    } catch (e) {
      throw Exception('Failed to delete gas station: $e');
    }
  }

  

  // Add or update rating with comment for a station
  static Future<void> setRatingWithComment({
    required String stationId,
    required String userId,
    required String userName,
    required double rating,
    String? comment,
  }) async {
    try {
      await gasStationsCollection
          .doc(stationId)
          .collection('ratings')
          .doc(userId)
          .set({
            'stationId': stationId,
            'userId': userId,
            'userName': userName,
            'rating': rating,
            'comment': comment ?? '',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to set rating with comment: $e');
    }
  }

  // Add or update rating with comment for a station (using station_ratings collection)
  static Future<void> setRatingWithCommentInStationRatings({
    required String stationId,
    required String userId,
    required String userName,
    required double rating,
    String? comment,
  }) async {
    try {
      // Create a unique document ID for the rating
      final docId = '${stationId}_$userId';
      await _db.collection('station_ratings').doc(docId).set({
        'stationId': stationId,
        'userId': userId,
        'userName': userName,
        'rating': rating,
        'comment': comment ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to set rating with comment in station_ratings: $e');
    }
  }

  // Get all ratings with comments for a specific station
  static Stream<QuerySnapshot> getStationRatingsWithComments(String stationId) {
    return gasStationsCollection
        .doc(stationId)
        .collection('ratings')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Get user's rating with comment for a specific station
  static Future<DocumentSnapshot?> getUserRatingWithComment(String stationId, String userId) async {
    return await gasStationsCollection
        .doc(stationId)
        .collection('ratings')
        .doc(userId)
        .get();
  }

  // Get average rating for a station including comments
  static Future<Map<String, dynamic>> getAverageRatingWithStats(String stationId) async {
    final query = await gasStationsCollection
        .doc(stationId)
        .collection('ratings')
        .get();

    if (query.docs.isEmpty) {
      return {
        'averageRating': 0.0,
        'ratingCount': 0,
        'commentCount': 0
      };
    }

    double totalRating = 0.0;
    int commentCount = 0;

    for (var doc in query.docs) {
      final data = doc.data() as Map<String, dynamic>;
      totalRating += data['rating'] ?? 0.0;
      if (data['comment'] != null && (data['comment'] as String).isNotEmpty) {
        commentCount++;
      }
    }

    return {
      'averageRating': totalRating / query.docs.length,
      'ratingCount': query.docs.length,
      'commentCount': commentCount
    };
  }

  // Stream gas station data for real-time updates
  static Stream<DocumentSnapshot> streamGasStation(String stationId) {
    return gasStationsCollection.doc(stationId).snapshots();
  }

  // Stream all gas stations for real-time updates
  static Stream<QuerySnapshot> streamAllGasStations() {
    return gasStationsCollection.snapshots();
  }

  // Stream gas stations by owner for real-time updates
  static Stream<QuerySnapshot> streamGasStationsByOwner(String ownerId) {
    return gasStationsCollection
        .where('ownerId', isEqualTo: ownerId)
        .snapshots();
  }

  // Price History Methods

  // Record price change in history
  static Future<void> recordPriceChange({
    required String stationId,
    required String stationName,
    required String stationBrand,
    required Map<String, double> prices,
  }) async {
    try {
      final timestamp = DateTime.now();
      
      for (final entry in prices.entries) {
        final fuelType = entry.key;
        final price = entry.value;
        
        if (price > 0) {
          await gasStationsCollection
              .doc(stationId)
              .collection('price_history')
              .add({
                'stationId': stationId,
                'stationName': stationName,
                'stationBrand': stationBrand,
                'fuelType': fuelType,
                'price': price,
                'timestamp': Timestamp.fromDate(timestamp),
              });
        }
      }
    } catch (e) {
      throw Exception('Failed to record price change: $e');
    }
  }

  // Get user's assigned gas stations
  static Future<List<Map<String, dynamic>>> getUserAssignedStations(String userId) async {
    try {
      print('[DEBUG] Getting assigned stations for user: $userId');
      
      final userDoc = await usersCollection.doc(userId).get();
      if (!userDoc.exists) {
        print('[DEBUG] User document does not exist for userId: $userId');
        return [];
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final stationIds = List<String>.from(userData['assignedStations'] ?? []);
      
      print('[DEBUG] Found assigned station IDs: $stationIds');

      // If no assigned stations, try to get stations by owner ID as fallback
      if (stationIds.isEmpty) {
        print('[DEBUG] No assigned stations found, falling back to stations by owner ID');
        return await getGasStationsByOwner(userId);
      }

      final stations = <Map<String, dynamic>>[];
      for (final stationId in stationIds) {
        try {
          final stationData = await getGasStation(stationId);
          if (stationData != null) {
            stationData['id'] = stationId;
            stations.add(stationData);
            print('[DEBUG] Added station: $stationId');
          } else {
            print('[DEBUG] Station not found: $stationId');
          }
        } catch (e) {
          print('[ERROR] Error loading station $stationId: $e');
        }
      }
      
      print('[DEBUG] Returning ${stations.length} stations for user $userId');
      return stations;
    } catch (e) {
      print('[ERROR] Failed to get user assigned stations: $e');
      // Fallback to stations by owner ID in case of error
      try {
        print('[DEBUG] Falling back to getGasStationsByOwner due to error');
        return await getGasStationsByOwner(userId);
      } catch (fallbackError) {
        print('[ERROR] Fallback also failed: $fallbackError');
        return [];
      }
    }
  }

  // Assign gas station to user (for owners)
  static Future<void> assignStationToUser({
    required String stationId,
    required String userId,
  }) async {
    try {
      await usersCollection.doc(userId).update({
        'assignedStations': FieldValue.arrayUnion([stationId]),
      });
    } catch (e) {
      throw Exception('Failed to assign station to user: $e');
    }
  }

  // Remove gas station assignment from user
  static Future<void> removeStationFromUser({
    required String stationId,
    required String userId,
  }) async {
    try {
      await usersCollection.doc(userId).update({
        'assignedStations': FieldValue.arrayRemove([stationId]),
      });
    } catch (e) {
      throw Exception('Failed to remove station from user: $e');
    }
  }

  // Get price history for a specific station and fuel type
  static Future<List<PriceHistory>> getPriceHistory({
    required String stationId,
    String? fuelType,
    int? daysBack,
  }) async {
    try {
      print('DEBUG: Querying price history for station: $stationId, fuelType: $fuelType, daysBack: $daysBack');

      Query query = gasStationsCollection
          .doc(stationId)
          .collection('price_history')
          .orderBy('timestamp', descending: true);

      // Apply fuel type filter if specified
      if (fuelType != null && fuelType.isNotEmpty) {
        query = query.where('fuelType', isEqualTo: fuelType);
        print('DEBUG: Applying fuel type filter: $fuelType');
      } else {
        print('DEBUG: No fuel type filter applied (All Fuel Types)');
      }

      // Apply date filter if specified
      if (daysBack != null) {
        final cutoffDate = DateTime.now().subtract(Duration(days: daysBack));
        query = query.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoffDate));
        print('DEBUG: Applying date filter: $cutoffDate');
      }

      final querySnapshot = await query.get();
      print('DEBUG: Found ${querySnapshot.docs.length} price history documents');

      final priceHistory = querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final priceHistoryItem = PriceHistory(
          id: doc.id,
          stationId: data['stationId'] ?? '',
          stationName: data['stationName'] ?? '',
          stationBrand: data['stationBrand'] ?? '',
          fuelType: data['fuelType'] ?? '',
          price: (data['price'] as num).toDouble(),
          timestamp: (data['timestamp'] as Timestamp).toDate(),
        );
        print('DEBUG: Price history item: ${priceHistoryItem.fuelType} - ${priceHistoryItem.price} at ${priceHistoryItem.timestamp}');
        return priceHistoryItem;
      }).toList();

      print('DEBUG: Returning ${priceHistory.length} price history records');
      return priceHistory;
    } catch (e) {
      // Handle permission errors gracefully
      if (e.toString().contains('PERMISSION_DENIED') || e.toString().contains('Missing or insufficient permissions')) {
        print('Permission denied accessing price history for station: $stationId');
        return [];
      }
      throw Exception('Failed to get price history: $e');
    }
  }

  // Get price history for all stations owned by a user
  static Future<List<PriceHistory>> getPriceHistoryByOwner({
    required String ownerId,
    String? fuelType,
    int? daysBack,
  }) async {
    try {
      // First get all stations owned by the user
      final stations = await getGasStationsByOwner(ownerId);
      final allHistory = <PriceHistory>[];

      for (final station in stations) {
        final stationId = station['id'] as String;
        final stationHistory = await getPriceHistory(
          stationId: stationId,
          fuelType: fuelType,
          daysBack: daysBack,
        );
        allHistory.addAll(stationHistory);
      }

      // Sort by timestamp descending
      allHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return allHistory;
    } catch (e) {
      // Handle permission errors gracefully
      if (e.toString().contains('PERMISSION_DENIED') || e.toString().contains('Missing or insufficient permissions')) {
        print('Permission denied accessing price history for owner: $ownerId');
        return [];
      }
      throw Exception('Failed to get price history by owner: $e');
    }
  }

  // Get all price history across all stations
  static Future<List<PriceHistory>> getAllPriceHistory({
    String? fuelType,
    int? daysBack,
  }) async {
    try {
      Query query = gasStationsCollection
          .orderBy('lastUpdated', descending: true);

      final querySnapshot = await query.get();
      final allHistory = <PriceHistory>[];

      for (final stationDoc in querySnapshot.docs) {
        final stationId = stationDoc.id;
        final stationData = stationDoc.data() as Map<String, dynamic>;
        final stationName = stationData['name'] as String? ?? '';
        final stationBrand = stationData['brand'] as String? ?? '';

        Query historyQuery = gasStationsCollection
            .doc(stationId)
            .collection('price_history')
            .orderBy('timestamp', descending: true);

        // Apply fuel type filter if specified
        if (fuelType != null && fuelType.isNotEmpty) {
          historyQuery = historyQuery.where('fuelType', isEqualTo: fuelType);
        }

        // Apply date filter if specified
        if (daysBack != null) {
          final cutoffDate = DateTime.now().subtract(Duration(days: daysBack));
          historyQuery = historyQuery.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoffDate));
        }

        final historySnapshot = await historyQuery.get();

        final stationHistory = historySnapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return PriceHistory(
            id: doc.id,
            stationId: stationId,
            stationName: data['stationName'] ?? stationName,
            stationBrand: data['stationBrand'] ?? stationBrand,
            fuelType: data['fuelType'] ?? '',
            price: (data['price'] as num).toDouble(),
            timestamp: (data['timestamp'] as Timestamp).toDate(),
          );
        }).toList();

        allHistory.addAll(stationHistory);
      }

      // Sort by timestamp descending
      allHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return allHistory;
    } catch (e) {
      // Handle permission errors gracefully
      if (e.toString().contains('PERMISSION_DENIED') || e.toString().contains('Missing or insufficient permissions')) {
        print('Permission denied accessing all price history');
        return [];
      }
      throw Exception('Failed to get all price history: $e');
    }
  }

  // Favorites Management Methods

  // Get user's favorite gas station IDs
  static Future<List<String>> getUserFavorites(String userId) async {
    try {
      final doc = await usersCollection.doc(userId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return List<String>.from(data['favorites'] ?? []);
      }
      return [];
    } catch (e) {
      throw Exception('Failed to get user favorites: $e');
    }
  }

  // Add a gas station to user's favorites
  static Future<void> addFavorite(String userId, String stationId) async {
    try {
      await usersCollection.doc(userId).update({
        'favorites': FieldValue.arrayUnion([stationId]),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to add favorite: $e');
    }
  }

  // Remove a gas station from user's favorites
  static Future<void> removeFavorite(String userId, String stationId) async {
    try {
      await usersCollection.doc(userId).update({
        'favorites': FieldValue.arrayRemove([stationId]),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to remove favorite: $e');
    }
  }

  // Check if a station is favorited by user
  static Future<bool> isFavorite(String userId, String stationId) async {
    try {
      final favorites = await getUserFavorites(userId);
      return favorites.contains(stationId);
    } catch (e) {
      return false;
    }
  }

  // Stream user's favorites for real-time updates
  static Stream<List<String>> streamUserFavorites(String userId) {
    return usersCollection.doc(userId).snapshots().map((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return List<String>.from(data['favorites'] ?? []);
      }
      return [];
    });
  }
}
