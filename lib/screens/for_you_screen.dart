import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gas_station.dart' as models;
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gas_station_service.dart';
import '../services/user_preferences_service.dart';
import 'list_screen.dart';

class ForYouScreen extends StatefulWidget {
  final Function(String)? onNavigateToStation;

  const ForYouScreen({super.key, this.onNavigateToStation});

  @override
  State<ForYouScreen> createState() => ForYouScreenState();
}

class ForYouScreenState extends State<ForYouScreen> {
  List<Map<String, dynamic>> _offers = [];
  List<Map<String, dynamic>> _vouchers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  Set<String> _claimedOfferIds = {};
  Set<String> _redeemedVoucherIds = {};
  bool _isClaimsLoading = true;

  // Highlighting state
  String? _highlightedItemId;
  String? _highlightedType;
  final Map<String, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _loadPromotions();
    _loadUserClaimsAndRedemptions();
  }

  /// Highlight an item (offer or voucher) for a few seconds
  void highlightItem({required String itemId, required String type}) {
    setState(() {
      _highlightedItemId = itemId;
      _highlightedType = type;
    });

    // Remove highlight after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _highlightedItemId = null;
          _highlightedType = null;
        });
      }
    });

    // Scroll to the highlighted item after a short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      final key = _itemKeys[itemId];
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadPromotions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        FirestoreService.searchOffers(status: 'Active', limit: 50),
        FirestoreService.searchVouchers(status: 'Active', limit: 50),
      ]);

      if (!mounted) return;
      setState(() {
        _offers = results[0] as List<Map<String, dynamic>>;
        _vouchers = results[1] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading promotions: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUserClaimsAndRedemptions() async {
    final userId = AuthService().currentUser?.uid;
    if (userId == null) {
      setState(() => _isClaimsLoading = false);
      return;
    }

    try {
      final results = await Future.wait([
        FirestoreService.getUserClaimedOffers(userId),
        FirestoreService.getUserRedeemedVouchers(userId),
      ]);

      if (!mounted) return;
      setState(() {
        _claimedOfferIds =
            results[0].map((claimed) => claimed['offerId'] as String).toSet();
        _redeemedVoucherIds = results[1]
            .map((redeemed) => redeemed['voucherId'] as String)
            .toSet();
        _isClaimsLoading = false;
      });
    } catch (e) {
      print('Error loading user claims and redemptions: $e');
      if (mounted) {
        setState(() => _isClaimsLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredOffers {
    var filtered = _offers;

    // Filter out already claimed offers
    if (_isClaimsLoading == false) {
      filtered = filtered
          .where((offer) => !_claimedOfferIds.contains(offer['id']))
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((offer) {
        final title = (offer['title'] ?? '').toString().toLowerCase();
        final description =
            (offer['description'] ?? '').toString().toLowerCase();
        final stationName =
            (offer['stationName'] ?? '').toString().toLowerCase();
        return title.contains(_searchQuery.toLowerCase()) ||
            description.contains(_searchQuery.toLowerCase()) ||
            stationName.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    if (_selectedFilter != 'All') {
      filtered = filtered.where((offer) {
        if (_selectedFilter == 'Discount') {
          return offer['discount'] != null;
        } else if (_selectedFilter == 'Cashback') {
          return offer['cashback'] != null;
        }
        return true;
      }).toList();
    }

    return filtered;
  }

  List<Map<String, dynamic>> get _filteredVouchers {
    var filtered = _vouchers;

    // Filter out already redeemed vouchers
    if (_isClaimsLoading == false) {
      filtered = filtered
          .where((voucher) => !_redeemedVoucherIds.contains(voucher['id']))
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((voucher) {
        final title = (voucher['title'] ?? '').toString().toLowerCase();
        final description =
            (voucher['description'] ?? '').toString().toLowerCase();
        final stationName =
            (voucher['stationName'] ?? '').toString().toLowerCase();
        return title.contains(_searchQuery.toLowerCase()) ||
            description.contains(_searchQuery.toLowerCase()) ||
            stationName.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    if (_selectedFilter != 'All') {
      filtered = filtered.where((voucher) {
        if (_selectedFilter == 'Percentage') {
          return voucher['discountType'] == 'percentage';
        } else if (_selectedFilter == 'Fixed Amount') {
          return voucher['discountType'] == 'fixed_amount';
        } else if (_selectedFilter == 'Free Item') {
          return voucher['discountType'] == 'free_item';
        }
        return true;
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Theme.of(context).appBarTheme.backgroundColor,
            child: const TabBar(
              tabs: [
                Tab(text: 'Deals', icon: Icon(Icons.local_offer)),
                Tab(text: 'Favorites', icon: Icon(Icons.favorite)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildPromotionsList(),
                _buildFavoritesList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotionsList() {
    if (_offers.isEmpty && _vouchers.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // Search and Filter Bar
        _buildSearchAndFilterBar(),

        // Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              if (_filteredOffers.isNotEmpty) ...[
                _buildSectionTitle('Special Offers'),
                ..._buildOfferWidgets(),
                const SizedBox(height: 24),
              ],
              if (_filteredVouchers.isNotEmpty) ...[
                _buildSectionTitle('Available Vouchers'),
                ..._buildVoucherWidgets(),
                const SizedBox(height: 24),
              ],
              _buildSectionTitle('Rate a Station, Get a Reward!'),
              _buildReviewPrompt(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        children: [
          // Search Bar
          TextField(
            decoration: InputDecoration(
              hintText: 'Search offers and vouchers...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),

          const SizedBox(height: 12),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All'),
                _buildFilterChip('Discount'),
                _buildFilterChip('Cashback'),
                _buildFilterChip('Percentage'),
                _buildFilterChip('Fixed Amount'),
                _buildFilterChip('Free Item'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = selected ? label : 'All';
          });
        },
        selectedColor: Colors.blue.shade100,
        checkmarkColor: Colors.blue,
      ),
    );
  }

  List<Widget> _buildOfferWidgets() {
    if (_filteredOffers.isEmpty) {
      return [const Text('No special offers right now. Check back later!')];
    }

    return _filteredOffers.map((offer) {
      final offerId = offer['id'] as String? ?? '';
      final isHighlighted =
          _highlightedItemId == offerId && _highlightedType == 'offer';

      // Create a key for this item if it doesn't exist
      if (!_itemKeys.containsKey(offerId)) {
        _itemKeys[offerId] = GlobalKey();
      }

      return Card(
        key: _itemKeys[offerId],
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: isHighlighted ? 8 : 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: isHighlighted ? Colors.amber.shade50 : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _navigateToStation(offer['stationId']),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: isHighlighted
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber, width: 3),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.local_offer,
                          color: Colors.orange, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offer['title'] ?? 'Special Offer',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            offer['stationName'] ?? 'Unknown Station',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (offer['discount'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          offer['discount'],
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    if (offer['cashback'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          offer['cashback'],
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  offer['description'] ?? '',
                  style: const TextStyle(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Valid until: ${_formatDate(offer['validUntil'])}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _claimOffer(offer),
                      child: const Text('Claim Offer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildVoucherWidgets() {
    if (_filteredVouchers.isEmpty) {
      return [const Text('No vouchers available at the moment.')];
    }

    return _filteredVouchers.map((voucher) {
      final voucherId = voucher['id'] as String? ?? '';
      final isHighlighted =
          _highlightedItemId == voucherId && _highlightedType == 'voucher';

      // Create a key for this item if it doesn't exist
      if (!_itemKeys.containsKey(voucherId)) {
        _itemKeys[voucherId] = GlobalKey();
      }

      return Card(
        key: _itemKeys[voucherId],
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: isHighlighted ? 8 : 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: isHighlighted ? Colors.amber.shade50 : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _navigateToStation(voucher['stationId']),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: isHighlighted
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber, width: 3),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.receipt,
                          color: Colors.purple, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            voucher['title'] ?? 'Special Voucher',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            voucher['stationName'] ?? 'Unknown Station',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _getVoucherDisplayValue(voucher),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  voucher['description'] ?? '',
                  style: const TextStyle(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.confirmation_number, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Code: ${voucher['code'] ?? 'N/A'}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () => _copyVoucherCode(voucher['code']),
                        tooltip: 'Copy Code',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Valid until: ${_formatDate(voucher['validUntil'])}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _redeemVoucher(voucher),
                      child: const Text('Redeem'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildReviewPrompt() {
    // For now, picks a random station that the user hasn't rated yet.
    final unratedStations = GasStationService.getAllGasStations()
        .where((s) => s.rating == 0.0)
        .toList();
    if (unratedStations.isEmpty) return const SizedBox.shrink();

    final stationToReview = (unratedStations..shuffle()).first;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
                'Get a voucher for your next review at ${stationToReview.name}!'),
            const SizedBox(height: 10),
            ElevatedButton(
              child: const Text('Rate Now'),
              onPressed: () {
                _navigateToStation(
                    stationToReview.id ?? stationToReview.name ?? '');
              },
            )
          ],
        ),
      ),
    );
  }

  String _getVoucherDisplayValue(Map<String, dynamic> voucher) {
    final discountType = voucher['discountType'] ?? '';
    final discountValue = voucher['discountValue'] ?? 0.0;

    if (discountType == 'percentage') {
      return '${discountValue.toInt()}% OFF';
    } else if (discountType == 'fixed_amount') {
      return '₱${discountValue.toInt()} OFF';
    } else if (discountType == 'free_item') {
      return 'FREE ITEM';
    }
    return 'DISCOUNT';
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  Future<void> _copyVoucherCode(String? code) async {
    if (code == null || code.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voucher code copied!')),
    );
  }

// Replace the _claimOffer and _redeemVoucher methods in for_you_screen.dart

  Future<void> _claimOffer(Map<String, dynamic> offer) async {
    final user = AuthService().currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to claim offers')),
      );
      return;
    }

    // Validate required fields
    final stationId = offer['stationId'] as String?;
    final offerId = offer['id'] as String?;

    if (stationId == null || stationId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid station information')),
      );
      return;
    }

    if (offerId == null || offerId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid offer information')),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      await FirestoreService.claimOffer(
        stationId: stationId,
        offerId: offerId,
        userId: user.uid,
        userName: user.displayName ?? user.email ?? 'User',
      );

      if (!mounted) return;
      // Dismiss loading dialog
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offer claimed successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh the offers list and user claims
      await Future.wait([
        _loadPromotions(),
        _loadUserClaimsAndRedemptions(),
      ]);
    } catch (e) {
      if (!mounted) return;
      // Dismiss loading dialog
      Navigator.of(context).pop();

      String errorMessage = 'Failed to claim offer';

      if (e.toString().contains('already claimed')) {
        errorMessage = 'You have already claimed this offer';
      } else if (e.toString().contains('expired')) {
        errorMessage = 'This offer has expired';
      } else if (e.toString().contains('maximum claims')) {
        errorMessage = 'This offer has reached maximum claims';
      } else if (e.toString().contains('PERMISSION_DENIED')) {
        errorMessage =
            'Permission denied. Please try again or contact support.';
      } else {
        errorMessage = 'Failed to claim offer: ${e.toString()}';
      }

      print('Error claiming offer: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _redeemVoucher(Map<String, dynamic> voucher) async {
    final user = AuthService().currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to redeem vouchers')),
      );
      return;
    }

    // Validate required fields
    final stationId = voucher['stationId'] as String?;
    final voucherId = voucher['id'] as String?;

    if (stationId == null || stationId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid station information')),
      );
      return;
    }

    if (voucherId == null || voucherId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid voucher information')),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      await FirestoreService.redeemVoucher(
        stationId: stationId,
        voucherId: voucherId,
        userId: user.uid,
        userName: user.displayName ?? user.email ?? 'User',
      );

      if (!mounted) return;
      // Dismiss loading dialog
      Navigator.of(context).pop();

      // Show success dialog with voucher code
      final voucherCode = voucher['code'] as String? ?? 'N/A';
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Voucher Redeemed!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your voucher has been redeemed successfully!'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Voucher Code:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            voucherCode,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            onPressed: () => _copyVoucherCode(voucherCode),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Show this code at the station to use your voucher.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      // Refresh the vouchers list and user redemptions
      await Future.wait([
        _loadPromotions(),
        _loadUserClaimsAndRedemptions(),
      ]);
    } catch (e) {
      if (!mounted) return;
      // Dismiss loading dialog
      Navigator.of(context).pop();

      String errorMessage = 'Failed to redeem voucher';

      if (e.toString().contains('already redeemed')) {
        errorMessage = 'You have already redeemed this voucher';
      } else if (e.toString().contains('expired')) {
        errorMessage = 'This voucher has expired';
      } else if (e.toString().contains('out of stock')) {
        errorMessage = 'This voucher is out of stock';
      } else if (e.toString().contains('maximum redemptions')) {
        errorMessage = 'This voucher has reached maximum redemptions';
      } else if (e.toString().contains('not active')) {
        errorMessage = 'This voucher is no longer active';
      } else if (e.toString().contains('PERMISSION_DENIED')) {
        errorMessage =
            'Permission denied. Please try again or contact support.';
      } else {
        errorMessage = 'Failed to redeem voucher: ${e.toString()}';
      }

      print('Error redeeming voucher: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _navigateToStation(String stationId) {
    if (stationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Unable to load station details. Please try again.')),
      );
      return;
    }

    if (widget.onNavigateToStation != null) {
      widget.onNavigateToStation!(stationId);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ListScreen(),
          settings: RouteSettings(arguments: {
            'showStationDetails': true,
            'stationId': stationId,
          }),
        ),
      );
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .headlineSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_offer_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Deals Available',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later for new offers and vouchers!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesList() {
    return ListenableBuilder(
      listenable: UserPreferencesService(),
      builder: (context, child) {
        final favoriteIds = UserPreferencesService().favoriteStationIds;
        final allStations = GasStationService.getAllGasStations();
        final favoriteStations =
            allStations.where((s) => favoriteIds.contains(s.id)).toList();

        if (favoriteStations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text(
                  'No favorites yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add stations to your favorites to see them here!',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: favoriteStations.length,
          itemBuilder: (context, index) {
            final station = favoriteStations[index];
            return _buildFavoriteStationTile(station);
          },
        );
      },
    );
  }

  Widget _buildFavoriteStationTile(models.GasStation station) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _navigateToStation(station.id ?? station.name ?? ''),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    child: Text(
                      (station.brand != null && station.brand!.isNotEmpty)
                          ? station.brand![0].toUpperCase()
                          : 'G',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          station.name ?? 'Unknown Station',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          station.address ?? 'No address available',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.favorite, color: Colors.red),
                    onPressed: () {
                      UserPreferencesService()
                          .toggleFavoriteStation(station.id ?? '');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        (station.rating ?? 0.0).toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    '₱${_getStationPrice(station)}/L',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStationPrice(models.GasStation station) {
    final fuelType = UserPreferencesService().preferredFuelType.toLowerCase();
    if (station.prices != null && station.prices!.containsKey(fuelType)) {
      return station.prices![fuelType]!.toStringAsFixed(2);
    }
    // Fallback if preferred fuel type not found
    if (station.prices != null && station.prices!.isNotEmpty) {
      return station.prices!.values.first.toStringAsFixed(2);
    }
    return '0.00';
  }
}
