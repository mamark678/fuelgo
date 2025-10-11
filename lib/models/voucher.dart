class Voucher {
  final String id;
  final String title;
  final String description;
  final String code;
  final DateTime validUntil;
  final String stationId;
  final String stationName;
  final DateTime createdAt;
  final String? imageUrl;
  final String? discountType; // 'percentage', 'fixed_amount', 'free_item'
  final double? discountValue;
  final int minPurchase;
  final int maxUses;
  final int used;
  final String status;
  final List<String> applicableFuelTypes;
  final String? termsAndConditions;
  final bool isNotificationEnabled;

  Voucher({
    required this.id,
    required this.title,
    required this.description,
    required this.code,
    required this.validUntil,
    required this.stationId,
    required this.stationName,
    required this.createdAt,
    this.imageUrl,
    this.discountType,
    this.discountValue,
    this.minPurchase = 0,
    this.maxUses = 0,
    this.used = 0,
    this.status = 'Active',
    this.applicableFuelTypes = const ['Regular', 'Premium', 'Diesel'],
    this.termsAndConditions,
    this.isNotificationEnabled = true,
  });

  factory Voucher.fromMap(Map<String, dynamic> map) {
    return Voucher(
      id: map['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: map['title'] ?? 'Untitled Voucher',
      description: map['description'] ?? '',
      code: map['code'] ?? '',
      validUntil: map['validUntil'] != null 
          ? DateTime.parse(map['validUntil'])
          : DateTime.now().add(const Duration(days: 30)),
      stationId: map['stationId'] ?? '',
      stationName: map['stationName'] ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      imageUrl: map['imageUrl'],
      discountType: map['discountType'],
      discountValue: map['discountValue']?.toDouble(),
      minPurchase: (map['minPurchase'] ?? 0).toInt(),
      maxUses: (map['maxUses'] ?? 0).toInt(),
      used: (map['used'] ?? 0).toInt(),
      status: map['status'] ?? 'Active',
      applicableFuelTypes: List<String>.from(map['applicableFuelTypes'] ?? ['Regular', 'Premium', 'Diesel']),
      termsAndConditions: map['termsAndConditions'],
      isNotificationEnabled: map['isNotificationEnabled'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'code': code,
      'validUntil': validUntil.toIso8601String(),
      'stationId': stationId,
      'stationName': stationName,
      'createdAt': createdAt.toIso8601String(),
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (discountType != null) 'discountType': discountType,
      if (discountValue != null) 'discountValue': discountValue,
      'minPurchase': minPurchase,
      'maxUses': maxUses,
      'used': used,
      'status': status,
      'applicableFuelTypes': applicableFuelTypes,
      if (termsAndConditions != null) 'termsAndConditions': termsAndConditions,
      'isNotificationEnabled': isNotificationEnabled,
    };
  }

  bool get isExpired => validUntil.isBefore(DateTime.now());
  bool get isValid => !isExpired && status == 'Active';
  bool get isActive => status == 'Active' && !isExpired;
  bool get isPaused => status == 'Paused';
  bool get canBeClaimed => isActive && used < maxUses;
  int get remainingUses => maxUses - used;

  String get displayValue {
    if (discountType == 'percentage' && discountValue != null) {
      return '${discountValue!.toInt()}% OFF';
    } else if (discountType == 'fixed_amount' && discountValue != null) {
      return '₱${discountValue!.toInt()} OFF';
    } else if (discountType == 'free_item') {
      return 'FREE ITEM';
    }
    return 'DISCOUNT';
  }
}
