class Offer {
  final String id;
  final String title;
  final String description;
  final DateTime validUntil;
  final String status;
  final String? discount;
  final String? cashback;
  final int minPurchase;
  final int maxUses;
  final int used;
  final String stationId;
  final String stationName;
  final DateTime createdAt;
  final String? imageUrl;
  final List<String> applicableFuelTypes;
  final String? termsAndConditions;
  final double? discountPercentage;
  final double? discountAmount;
  final bool isNotificationEnabled;

  Offer({
    required this.id,
    required this.title,
    required this.description,
    required this.validUntil,
    this.status = 'Active',
    this.discount,
    this.cashback,
    this.minPurchase = 0,
    this.maxUses = 0,
    this.used = 0,
    required this.stationId,
    required this.stationName,
    required this.createdAt,
    this.imageUrl,
    this.applicableFuelTypes = const ['Regular', 'Premium', 'Diesel'],
    this.termsAndConditions,
    this.discountPercentage,
    this.discountAmount,
    this.isNotificationEnabled = true,
  });

  factory Offer.fromMap(Map<String, dynamic> map) {
    return Offer(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      validUntil: map['validUntil'] != null 
          ? DateTime.parse(map['validUntil'])
          : DateTime.now().add(const Duration(days: 30)),
      status: map['status'] ?? 'Active',
      discount: map['discount'],
      cashback: map['cashback'],
      minPurchase: (map['minPurchase'] ?? 0).toInt(),
      maxUses: (map['maxUses'] ?? 0).toInt(),
      used: (map['used'] ?? 0).toInt(),
      stationId: map['stationId'] ?? '',
      stationName: map['stationName'] ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      imageUrl: map['imageUrl'],
      applicableFuelTypes: List<String>.from(map['applicableFuelTypes'] ?? ['Regular', 'Premium', 'Diesel']),
      termsAndConditions: map['termsAndConditions'],
      discountPercentage: map['discountPercentage']?.toDouble(),
      discountAmount: map['discountAmount']?.toDouble(),
      isNotificationEnabled: map['isNotificationEnabled'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'validUntil': validUntil.toIso8601String(),
      'status': status,
      if (discount != null) 'discount': discount,
      if (cashback != null) 'cashback': cashback,
      'minPurchase': minPurchase,
      'maxUses': maxUses,
      'used': used,
      'stationId': stationId,
      'stationName': stationName,
      'createdAt': createdAt.toIso8601String(),
      if (imageUrl != null) 'imageUrl': imageUrl,
      'applicableFuelTypes': applicableFuelTypes,
      if (termsAndConditions != null) 'termsAndConditions': termsAndConditions,
      if (discountPercentage != null) 'discountPercentage': discountPercentage,
      if (discountAmount != null) 'discountAmount': discountAmount,
      'isNotificationEnabled': isNotificationEnabled,
    };
  }

  bool get isExpired => validUntil.isBefore(DateTime.now());
  bool get isActive => status == 'Active' && !isExpired;
  bool get isPaused => status == 'Paused';
  bool get canBeClaimed => isActive && used < maxUses;
  int get remainingUses => maxUses - used;

  String get offerType {
    if (discount != null) return 'Discount';
    if (cashback != null) return 'Cashback';
    return 'Special Offer';
  }

  String get displayValue {
    if (discount != null) return '$discount OFF';
    if (cashback != null) return '$cashback Back';
    return 'Special Offer';
  }
}
