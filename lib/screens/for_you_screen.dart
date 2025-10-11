import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/gas_station_service.dart';
import 'list_screen.dart';

class ForYouScreen extends StatefulWidget {
  final Function(String)? onNavigateToStation;

  const ForYouScreen({super.key, this.onNavigateToStation});

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  List<Map<String, dynamic>> _offers = [];
  List<Map<String, dynamic>> _vouchers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadPromotions();
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
      
      setState(() {
        _offers = results[0] as List<Map<String, dynamic>>;
        _vouchers = results[1] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading promotions: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredOffers {
    var filtered = _offers;
    
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((offer) {
        final title = (offer['title'] ?? '').toString().toLowerCase();
        final description = (offer['description'] ?? '').toString().toLowerCase();
        final stationName = (offer['stationName'] ?? '').toString().toLowerCase();
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
    
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((voucher) {
        final title = (voucher['title'] ?? '').toString().toLowerCase();
        final description = (voucher['description'] ?? '').toString().toLowerCase();
        final stationName = (voucher['stationName'] ?? '').toString().toLowerCase();
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
    return Scaffold(
      appBar: AppBar(
  title: const Text(
    'Deals for You',
    style: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 20,
    ),
  ),
),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildPromotionsList(),
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
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _navigateToStation(offer['stationId']),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                      child: const Icon(Icons.local_offer, color: Colors.orange, size: 24),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _navigateToStation(voucher['stationId']),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                      child: const Icon(Icons.receipt, color: Colors.purple, size: 24),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    final unratedStations = GasStationService.getAllGasStations().where((s) => s.rating == 0.0).toList();
    if (unratedStations.isEmpty) return const SizedBox.shrink();

    final stationToReview = (unratedStations..shuffle()).first;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Get a voucher for your next review at ${stationToReview.name}!'),
            const SizedBox(height: 10),
            ElevatedButton(
              child: const Text('Rate Now'),
              onPressed: () {
                _navigateToStation(stationToReview.id ?? stationToReview.name ?? '');
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

  Future<void> _claimOffer(Map<String, dynamic> offer) async {
    final user = AuthService().currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to claim offers')),
      );
      return;
    }

    try {
      await FirestoreService.claimOffer(
        stationId: offer['stationId'],
        offerId: offer['id'],
        userId: user.uid,
        userName: user.displayName ?? 'User',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offer claimed successfully!')),
      );
      
      // Refresh the offers list
      _loadPromotions();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to claim offer: $e')),
      );
    }
  }

  Future<void> _redeemVoucher(Map<String, dynamic> voucher) async {
    final user = AuthService().currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to redeem vouchers')),
      );
      return;
    }

    try {
      await FirestoreService.redeemVoucher(
        stationId: voucher['stationId'],
        voucherId: voucher['id'],
        userId: user.uid,
        userName: user.displayName ?? 'User',
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voucher redeemed successfully!')),
      );
      
      // Refresh the vouchers list
      _loadPromotions();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to redeem voucher: $e')),
      );
    }
  }

  void _navigateToStation(String stationId) {
    if (stationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load station details. Please try again.')),
      );
      return;
    }

    if (widget.onNavigateToStation != null) {
      widget.onNavigateToStation!(stationId);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ListScreen(),
          settings: RouteSettings(
            arguments: {
              'showStationDetails': true,
              'stationId': stationId,
            }
          ),
        ),
      );
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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

}
