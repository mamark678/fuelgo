import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/voucher_code_service.dart';

class OffersTab extends StatefulWidget {
  const OffersTab({super.key});

  @override
  State<OffersTab> createState() => _OffersTabState();
}

class _OffersTabState extends State<OffersTab> {
  List<Map<String, dynamic>> _offers = [];
  List<Map<String, dynamic>> _vouchers = [];
  Map<String, dynamic> _analytics = {};
  bool _isLoading = true;
  String? _userId;
  String _filter = 'All';
  String _voucherFilter = 'All';
  int _selectedTabIndex = 1; // Start with Offers tab

  @override
  void initState() {
    super.initState();
    _loadUserAndOffers();
  }

  Future<void> _loadUserAndOffers() async {
    final user = AuthService().currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    _userId = user.uid;
    await _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await Future.wait([
        _loadOffers(),
        _loadVouchers(),
        _loadAnalytics(),
      ]);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load data: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadOffers() async {
    if (_userId == null) return;
    try {
      final offers = await FirestoreService.getOffersByOwner(_userId!);
      setState(() {
        _offers = offers;
      });
    } catch (e) {
      print('Error loading offers: $e');
    }
  }

  Future<void> _loadVouchers() async {
    if (_userId == null) return;
    try {
      final vouchers = await FirestoreService.getVouchersByOwner(_userId!);
      setState(() {
        _vouchers = vouchers;
      });
    } catch (e) {
      print('Error loading vouchers: $e');
    }
  }

  Future<void> _loadAnalytics() async {
    if (_userId == null) return;
    try {
      final analytics = await FirestoreService.getCombinedAnalytics(_userId!);
      setState(() {
        _analytics = analytics;
      });
    } catch (e) {
      print('Error loading analytics: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredOffers {
    if (_filter == 'All') return _offers;
    return _offers.where((offer) {
      final status = offer['status'] ?? 'Active';
      return status == _filter;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredVouchers {
    if (_voucherFilter == 'All') return _vouchers;
    return _vouchers.where((voucher) {
      final status = voucher['status'] ?? 'Active';
      return status == _voucherFilter;
    }).toList();
  }

  Future<void> _createOffer() async {
    if (_userId == null) return;
    
    final newOffer = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => OfferFormDialog(ownerId: _userId!),
    );
    if (newOffer != null && _userId != null) {
      try {
        await FirestoreService.addOffer(
          stationId: newOffer['stationId'],
          offer: newOffer,
        );
        await _loadAllData();
        
        // Send notification if enabled
        if (newOffer['isNotificationEnabled'] == true) {
          await NotificationService().showOfferNotification(
            title: 'New Offer Available!',
            body: '${newOffer['title']} at ${newOffer['stationName']}',
            stationName: newOffer['stationName'],
            offerId: newOffer['id'],
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add offer: $e')),
        );
      }
    }
  }

  Future<void> _createVoucher() async {
    if (_userId == null) return;
    
    final newVoucher = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => VoucherFormDialog(ownerId: _userId!),
    );
    if (newVoucher != null && _userId != null) {
      try {
        await FirestoreService.addVoucher(
          stationId: newVoucher['stationId'],
          voucher: newVoucher,
        );
        await _loadAllData();
        
        // Send notification if enabled
        if (newVoucher['isNotificationEnabled'] == true) {
          await NotificationService().showVoucherNotification(
            title: 'New Voucher Available!',
            body: '${newVoucher['title']} at ${newVoucher['stationName']}',
            stationName: newVoucher['stationName'],
            voucherId: newVoucher['id'],
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add voucher: $e')),
        );
      }
    }
  }

  Future<void> _editOffer(Map<String, dynamic> offer) async {
    if (_userId == null) return;
    
    final updatedOffer = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => OfferFormDialog(offer: offer, ownerId: _userId!),
    );
    if (updatedOffer != null && _userId != null) {
      try {
        await FirestoreService.updateOffer(
          stationId: offer['stationId'],
          oldOffer: offer,
          newOffer: updatedOffer,
        );
        await _loadAllData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update offer: $e')),
        );
      }
    }
  }

  Future<void> _editVoucher(Map<String, dynamic> voucher) async {
    if (_userId == null) return;
    
    final updatedVoucher = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => VoucherFormDialog(voucher: voucher, ownerId: _userId!),
    );
    if (updatedVoucher != null && _userId != null) {
      try {
        await FirestoreService.updateVoucher(
          stationId: voucher['stationId'],
          oldVoucher: voucher,
          newVoucher: updatedVoucher,
        );
        await _loadAllData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update voucher: $e')),
        );
      }
    }
  }

  Future<void> _pauseOffer(Map<String, dynamic> offer) async {
    if (_userId == null) return;
    try {
      final updatedOffer = Map<String, dynamic>.from(offer);
      updatedOffer['status'] = updatedOffer['status'] == 'Paused' ? 'Active' : 'Paused';
      await FirestoreService.updateOffer(
        stationId: offer['stationId'],
        oldOffer: offer,
        newOffer: updatedOffer,
      );
      await _loadAllData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update offer status: $e')),
      );
    }
  }

  Future<void> _pauseVoucher(Map<String, dynamic> voucher) async {
    if (_userId == null) return;
    try {
      final updatedVoucher = Map<String, dynamic>.from(voucher);
      updatedVoucher['status'] = updatedVoucher['status'] == 'Paused' ? 'Active' : 'Paused';
      await FirestoreService.updateVoucher(
        stationId: voucher['stationId'],
        oldVoucher: voucher,
        newVoucher: updatedVoucher,
      );
      await _loadAllData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update voucher status: $e')),
      );
    }
  }

  Future<void> _deleteOffer(Map<String, dynamic> offer) async {
    if (_userId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Offer'),
        content: const Text('Are you sure you want to delete this offer?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await FirestoreService.deleteOffer(
          stationId: offer['stationId'],
          offer: offer,
        );
        await _loadAllData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete offer: $e')),
        );
      }
    }
  }

  Future<void> _deleteVoucher(Map<String, dynamic> voucher) async {
    if (_userId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Voucher'),
        content: const Text('Are you sure you want to delete this voucher?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await FirestoreService.deleteVoucher(
          stationId: voucher['stationId'],
          voucher: voucher,
        );
        await _loadAllData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete voucher: $e')),
        );
      }
    }
  }

  Widget _buildOfferCard(Map<String, dynamic> offer) {
    final title = offer['title'] ?? '';
    final discount = offer['discount'] ?? '';
    final cashback = offer['cashback'] ?? '';
    final validUntil = offer['validUntil'] != null
        ? DateTime.parse(offer['validUntil'])
        : null;
    final status = offer['status'] ?? 'Active';
    final used = offer['used'] ?? 0;
    final maxUses = offer['maxUses'] ?? 0;
    final minPurchase = offer['minPurchase'] ?? 0;

    Color statusColor;
    switch (status) {
      case 'Active':
        statusColor = Colors.green;
        break;
      case 'Paused':
        statusColor = Colors.orange;
        break;
      case 'Expired':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title, 
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            if (discount.isNotEmpty)
              Text('$discount OFF', style: const TextStyle(fontSize: 16, color: Colors.blue, fontWeight: FontWeight.bold)),
            if (cashback.isNotEmpty)
              Text('$cashback Back', style: const TextStyle(fontSize: 16, color: Colors.blue, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // Use Column instead of Row to prevent overflow
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Valid Until: ${validUntil != null ? validUntil.toLocal().toString().split(' ')[0] : 'N/A'}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Used $used/$maxUses',
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        'Min. ₱$minPurchase',
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Wrap action buttons to prevent overflow
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _editOffer(offer), 
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: () => _pauseOffer(offer), 
                  child: Text(
                    offer['status'] == 'Paused' ? 'Resume' : 'Pause', 
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
                TextButton(
                  onPressed: () => _deleteOffer(offer), 
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoucherCard(Map<String, dynamic> voucher) {
    final title = voucher['title'] ?? '';
    final code = voucher['code'] ?? '';
    final discountType = voucher['discountType'] ?? '';
    final discountValue = voucher['discountValue'] ?? 0.0;
    final validUntil = voucher['validUntil'] != null
        ? DateTime.parse(voucher['validUntil'])
        : null;
    final status = voucher['status'] ?? 'Active';
    final used = voucher['used'] ?? 0;
    final maxUses = voucher['maxUses'] ?? 0;
    final minPurchase = voucher['minPurchase'] ?? 0;

    Color statusColor;
    switch (status) {
      case 'Active':
        statusColor = Colors.green;
        break;
      case 'Paused':
        statusColor = Colors.orange;
        break;
      case 'Expired':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    String displayValue = '';
    if (discountType == 'percentage') {
      displayValue = '${discountValue.toInt()}% OFF';
    } else if (discountType == 'fixed_amount') {
      displayValue = '₱${discountValue.toInt()} OFF';
    } else if (discountType == 'free_item') {
      displayValue = 'FREE ITEM';
    } else {
      displayValue = 'DISCOUNT';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title, 
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              displayValue,
              style: const TextStyle(fontSize: 16, color: Colors.purple, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Code: $code',
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Valid Until: ${validUntil != null ? validUntil.toLocal().toString().split(' ')[0] : 'N/A'}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Used $used/$maxUses',
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        'Min. ₱$minPurchase',
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _editVoucher(voucher), 
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: () => _pauseVoucher(voucher), 
                  child: Text(
                    voucher['status'] == 'Paused' ? 'Resume' : 'Pause', 
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
                TextButton(
                  onPressed: () => _deleteVoucher(voucher), 
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterButtons() {
    const filters = ['All', 'Active', 'Paused', 'Expired'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: filters.map((filter) {
          final isSelected = _filter == filter;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected ? Colors.blue : Colors.grey.shade200,
                foregroundColor: isSelected ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                elevation: 0,
              ),
              onPressed: () {
                setState(() {
                  _filter = filter;
                });
              },
              child: Text(filter),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVoucherFilterButtons() {
    const filters = ['All', 'Active', 'Paused', 'Expired'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: filters.map((filter) {
          final isSelected = _voucherFilter == filter;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected ? Colors.purple : Colors.grey.shade200,
                foregroundColor: isSelected ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                elevation: 0,
              ),
              onPressed: () {
                setState(() {
                  _voucherFilter = filter;
                });
              },
              child: Text(filter),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllData,
              child: Column(
                children: [
                  // Summary cards
                  Padding(
  padding: const EdgeInsets.all(12),
  child: Wrap(
    spacing: 12,
    runSpacing: 12,
    alignment: WrapAlignment.spaceEvenly,
    children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 340, minWidth: 150),
        child: SummaryCard(
          title: 'Active Offers',
          value: _offers.where((o) => (o['status'] ?? 'Active') == 'Active').length.toString(),
          color: Colors.blue,
        ),
      ),
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 340, minWidth: 150),
        child: SummaryCard(
          title: 'Active Vouchers',
          value: _vouchers.where((v) => (v['status'] ?? 'Active') == 'Active').length.toString(),
          color: Colors.purple,
        ),
      ),
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 340, minWidth: 150),
        child: SummaryCard(
          title: 'Total Claims',
          value: _analytics['offerAnalytics']?['totalClaims']?.toString() ?? '0',
          color: Colors.green,
        ),
      ),
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 340, minWidth: 150),
        child: SummaryCard(
          title: 'Revenue Impact',
          value: '₱${((_analytics['totalRevenueImpact'] ?? 0.0) as double).toStringAsFixed(0)}',
          color: Colors.orange,
        ),
      ),
    ],
  ),
),

                  // Tabs for Vouchers, Offers, Analytics
                  Expanded(
                    child: DefaultTabController(
                      length: 3,
                      initialIndex: 1,
                      child: Column(
                        children: [
                          const TabBar(
                            tabs: [
                              Tab(text: 'Vouchers'),
                              Tab(text: 'Offers'),
                              Tab(text: 'Analytics'),
                            ],
                            labelColor: Colors.blue,
                            unselectedLabelColor: Colors.grey,
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                // Vouchers tab content
                                Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: ElevatedButton.icon(
                                        onPressed: _createVoucher,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Create New Voucher'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.purple,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                    _buildVoucherFilterButtons(),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: _filteredVouchers.isEmpty
                                            ? const Center(
                                                child: Text(
                                                  'No vouchers found.\nCreate your first voucher!',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                                ),
                                              )
                                            : ListView.builder(
                                                itemCount: _filteredVouchers.length,
                                                itemBuilder: (context, index) {
                                                  return _buildVoucherCard(_filteredVouchers[index]);
                                                },
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                                // Offers tab content
                                Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: ElevatedButton.icon(
                                        onPressed: _createOffer,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Create New Offer'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                    _buildFilterButtons(),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: _filteredOffers.isEmpty
                                            ? const Center(
                                                child: Text(
                                                  'No offers found.\nCreate your first offer!',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                                ),
                                              )
                                            : ListView.builder(
                                                itemCount: _filteredOffers.length,
                                                itemBuilder: (context, index) {
                                                  return _buildOfferCard(_filteredOffers[index]);
                                                },
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                                // Analytics tab content
                                _buildAnalyticsTab(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAnalyticsTab() {
    if (_analytics.isEmpty) {
      return const Center(
        child: Text('No analytics data available yet. Create some offers and vouchers to see analytics!'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overview Cards
          _buildAnalyticsOverview(),
          const SizedBox(height: 24),
          
          // Charts Section
          _buildAnalyticsCharts(),
          const SizedBox(height: 24),
          
          // Performance Metrics
          _buildPerformanceMetrics(),
          const SizedBox(height: 24),
          
          // Recent Activity
          _buildRecentActivity(),
        ],
      ),
    );
  }

  Widget _buildAnalyticsOverview() {
    final offerAnalytics = _analytics['offerAnalytics'] ?? {};
    final voucherAnalytics = _analytics['voucherAnalytics'] ?? {};
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildAnalyticsCard(
                'Total Offers',
                '${offerAnalytics['totalOffers'] ?? 0}',
                'Active: ${offerAnalytics['activeOffers'] ?? 0}',
                Colors.blue,
                Icons.local_offer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAnalyticsCard(
                'Total Vouchers',
                '${voucherAnalytics['totalVouchers'] ?? 0}',
                'Active: ${voucherAnalytics['activeVouchers'] ?? 0}',
                Colors.purple,
                Icons.receipt,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildAnalyticsCard(
                'Total Claims',
                '${offerAnalytics['totalClaims'] ?? 0}',
                'Today: ${offerAnalytics['todayClaims'] ?? 0}',
                Colors.green,
                Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAnalyticsCard(
                'Total Redemptions',
                '${voucherAnalytics['totalRedemptions'] ?? 0}',
                'Today: ${voucherAnalytics['todayRedemptions'] ?? 0}',
                Colors.orange,
                Icons.card_giftcard,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnalyticsCard(String title, String value, String subtitle, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: color.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCharts() {
    final offerAnalytics = _analytics['offerAnalytics'] ?? {};
    final voucherAnalytics = _analytics['voucherAnalytics'] ?? {};
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Performance Charts',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        
        // Claims vs Redemptions Chart
        Container(
          height: 200,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              const Text(
                'Claims vs Redemptions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${offerAnalytics['totalClaims'] ?? 0}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Offer Claims',
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${voucherAnalytics['totalRedemptions'] ?? 0}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Voucher Redemptions',
                            style: TextStyle(fontSize: 12, color: Colors.purple),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Revenue Impact Chart
        Container(
          height: 120,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            children: [
              const Text(
                'Revenue Impact',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: Text(
                    '₱${((_analytics['totalRevenueImpact'] ?? 0.0) as double).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

Widget _buildPerformanceMetrics() {
  final offerAnalytics = _analytics['offerAnalytics'] ?? {};
  final voucherAnalytics = _analytics['voucherAnalytics'] ?? {};
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Performance Metrics',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      
      _buildMetricRow(
        'Average Claim Rate',
        '${((offerAnalytics['averageClaimRate'] ?? 0.0) as double).toStringAsFixed(1)} claims/offer',
        Colors.blue,
      ),
      _buildMetricRow(
        'Average Redemption Rate',
        '${((voucherAnalytics['averageRedemptionRate'] ?? 0.0) as double).toStringAsFixed(1)} redemptions/voucher',
        Colors.purple,
      ),
      _buildMetricRow(
        'Conversion Rate',
        '${((_analytics['conversionRate'] ?? 0.0) as double).toStringAsFixed(1)}%',
        Colors.green,
      ),
      _buildMetricRow(
        'Total Engagement',
        '${_analytics['totalEngagement'] ?? 0} interactions',
        Colors.orange,
      ),
    ],
  );
}

// Constrained single-row metric (title flexes; value constrained and right-aligned)
Widget _buildMetricRow(String title, String value, Color valueColor) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        // Title takes remaining flexible space and can wrap if needed
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16),
          ),
        ),

        const SizedBox(width: 8),

        // Value has a max width so it won't push beyond the screen.
        // Adjust maxWidth to taste for your layout.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 80, maxWidth: 160),
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    ),
  );
}


  Widget _buildRecentActivity() {
    final offerAnalytics = _analytics['offerAnalytics'] ?? {};
    final voucherAnalytics = _analytics['voucherAnalytics'] ?? {};
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        
        _buildActivityItem(
          'Today\'s Offer Claims',
          '${offerAnalytics['todayClaims'] ?? 0}',
          Icons.local_offer,
          Colors.blue,
        ),
        _buildActivityItem(
          'Today\'s Voucher Redemptions',
          '${voucherAnalytics['todayRedemptions'] ?? 0}',
          Icons.receipt,
          Colors.purple,
        ),
        _buildActivityItem(
          'Total Views',
          '${(offerAnalytics['totalViews'] ?? 0) + (voucherAnalytics['totalViews'] ?? 0)}',
          Icons.visibility,
          Colors.green,
        ),
        _buildActivityItem(
          'Unique Users',
          '${(offerAnalytics['uniqueUsers'] ?? 0) + (voucherAnalytics['uniqueUsers'] ?? 0)}',
          Icons.people,
          Colors.orange,
        ),
      ],
    );
  }

  Widget _buildActivityItem(String title, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class VoucherFormDialog extends StatefulWidget {
  final Map<String, dynamic>? voucher;
  final String ownerId;

  const VoucherFormDialog({super.key, this.voucher, required this.ownerId});

  @override
  State<VoucherFormDialog> createState() => _VoucherFormDialogState();
}

class _VoucherFormDialogState extends State<VoucherFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _codeController;
  late TextEditingController _discountValueController;
  late TextEditingController _minPurchaseController;
  late TextEditingController _maxUsesController;
  late TextEditingController _termsController;
  
  DateTime? _validUntil;
  String _status = 'Active';
  String? _selectedStationId;
  String _discountType = 'percentage';
  List<Map<String, dynamic>> _stations = [];
  bool _isLoadingStations = true;
  bool _isNotificationEnabled = true;
  List<String> _selectedFuelTypes = ['Regular', 'Premium', 'Diesel'];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.voucher?['title'] ?? '');
    _descriptionController = TextEditingController(text: widget.voucher?['description'] ?? '');
    _codeController = TextEditingController(text: widget.voucher?['code'] ?? '');
    _discountValueController = TextEditingController(text: widget.voucher?['discountValue']?.toString() ?? '');
    _minPurchaseController = TextEditingController(text: widget.voucher?['minPurchase']?.toString() ?? '0');
    _maxUsesController = TextEditingController(text: widget.voucher?['maxUses']?.toString() ?? '0');
    _termsController = TextEditingController(text: widget.voucher?['termsAndConditions'] ?? '');
    
    _validUntil = widget.voucher?['validUntil'] != null ? DateTime.parse(widget.voucher!['validUntil']) : null;
    _status = widget.voucher?['status'] ?? 'Active';
    _selectedStationId = widget.voucher?['stationId'];
    _discountType = widget.voucher?['discountType'] ?? 'percentage';
    _isNotificationEnabled = widget.voucher?['isNotificationEnabled'] ?? true;
    _selectedFuelTypes = List<String>.from(widget.voucher?['applicableFuelTypes'] ?? ['Regular', 'Premium', 'Diesel']);
    
    _loadStations();
  }

  Future<void> _loadStations() async {
    try {
      final stations = await FirestoreService.getUserAssignedStations(widget.ownerId);
      setState(() {
        _stations = stations;
        _isLoadingStations = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingStations = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _codeController.dispose();
    _discountValueController.dispose();
    _minPurchaseController.dispose();
    _maxUsesController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  Future<void> _pickValidUntilDate() async {
    final now = DateTime.now();
    DateTime initialDate = now;
    if (_validUntil != null && _validUntil!.isAfter(now)) {
      initialDate = _validUntil!;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _validUntil = picked;
      });
    }
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    if (_validUntil == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a valid until date')));
      return;
    }
    if (_selectedStationId == null && widget.voucher == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a gas station')));
      return;
    }
    
    final stationId = _selectedStationId ?? widget.voucher?['stationId'];
    if (stationId == null || stationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gas station selection is required')));
      return;
    }

    final discountValue = double.tryParse(_discountValueController.text) ?? 0.0;
    final minPurchase = int.tryParse(_minPurchaseController.text) ?? 0;
    final maxUses = int.tryParse(_maxUsesController.text) ?? 0;

    final newVoucher = {
      'id': widget.voucher?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'code': _codeController.text.trim(),
      'validUntil': _validUntil!.toIso8601String(),
      'status': _status,
      'stationId': stationId,
      'stationName': _stations.firstWhere((s) => s['id'] == stationId)['name'] ?? '',
      'createdAt': widget.voucher?['createdAt'] ?? DateTime.now().toIso8601String(),
      'discountType': _discountType,
      'discountValue': discountValue,
      'minPurchase': minPurchase,
      'maxUses': maxUses,
      'used': widget.voucher?['used'] ?? 0,
      'applicableFuelTypes': _selectedFuelTypes,
      'termsAndConditions': _termsController.text.trim(),
      'isNotificationEnabled': _isNotificationEnabled,
    };
    Navigator.of(context).pop(newVoucher);
  }

  Future<void> _generateVoucherCode() async {
    try {
      // Get the selected station to determine prefix
      String? prefix;
      if (_selectedStationId != null) {
        final selectedStation = _stations.firstWhere(
          (s) => s['id'] == _selectedStationId,
          orElse: () => {'brand': null},
        );
        prefix = VoucherCodeService.getSuggestedPrefix(selectedStation['brand']);
      }

      // Generate unique code
      final code = await VoucherCodeService.generateUniqueVoucherCode(
        prefix: prefix,
        length: 8,
      );

      // Update the text field
      _codeController.text = code;

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated unique code: $code'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate code: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.voucher == null ? 'Create Voucher' : 'Edit Voucher'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Station selection (only for new vouchers)
              if (widget.voucher == null) ...[
                _buildStationDropdown(),
                const SizedBox(height: 12),
              ],
              
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => value == null || value.isEmpty ? 'Please enter a title' : null,
              ),
              
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (value) => value == null || value.isEmpty ? 'Please enter a description' : null,
              ),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _codeController,
                      decoration: const InputDecoration(labelText: 'Voucher Code'),
                      validator: (value) => value == null || value.isEmpty ? 'Please enter a voucher code' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _generateVoucherCode,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Generate'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Discount Type and Value
              // Discount Type and Value (responsive)
LayoutBuilder(
  builder: (context, constraints) {
    final isNarrow = constraints.maxWidth < 420; // tweak breakpoint if needed
    if (isNarrow) {
      // Stack vertically on small widths
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _discountType,
            items: const [
              DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
              DropdownMenuItem(value: 'fixed_amount', child: Text('Fixed Amount')),
              DropdownMenuItem(value: 'free_item', child: Text('Free Item')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _discountType = value);
              }
            },
            decoration: const InputDecoration(labelText: 'Discount Type'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _discountValueController,
            decoration: InputDecoration(
              labelText: _discountType == 'percentage'
                  ? 'Percentage (%)'
                  : _discountType == 'fixed_amount'
                      ? 'Amount (₱)'
                      : 'Item Name',
            ),
            keyboardType: _discountType == 'free_item' ? TextInputType.text : TextInputType.number,
            validator: (value) {
              if (_discountType != 'free_item' && (value == null || value.isEmpty)) {
                return 'Please enter a value';
              }
              return null;
            },
          ),
        ],
      );
    }

    // Wide layout: keep them on one row
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _discountType,
            items: const [
              DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
              DropdownMenuItem(value: 'fixed_amount', child: Text('Fixed Amount')),
              DropdownMenuItem(value: 'free_item', child: Text('Free Item')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _discountType = value);
            },
            decoration: const InputDecoration(labelText: 'Discount Type'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _discountValueController,
            decoration: InputDecoration(
              labelText: _discountType == 'percentage'
                  ? 'Percentage (%)'
                  : _discountType == 'fixed_amount'
                      ? 'Amount (₱)'
                      : 'Item Name',
            ),
            keyboardType: _discountType == 'free_item' ? TextInputType.text : TextInputType.number,
            validator: (value) {
              if (_discountType != 'free_item' && (value == null || value.isEmpty)) {
                return 'Please enter a value';
              }
              return null;
            },
          ),
        ),
      ],
    );
  },
),

              
              const SizedBox(height: 12),
              
              // Min Purchase and Max Uses
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minPurchaseController,
                      decoration: const InputDecoration(labelText: 'Min Purchase (₱)'),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final val = int.tryParse(value ?? '');
                        if (val == null || val < 0) {
                          return 'Please enter a valid amount';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _maxUsesController,
                      decoration: const InputDecoration(labelText: 'Max Uses'),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final val = int.tryParse(value ?? '');
                        if (val == null || val < 0) {
                          return 'Please enter a valid number';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Valid Until Date
              Row(
  children: [
    const Text('Valid Until:'),
    const SizedBox(width: 8),
    Expanded(
      child: Text(
        _validUntil != null ? _validUntil!.toLocal().toString().split(' ')[0] : 'Not set',
        overflow: TextOverflow.ellipsis,
      ),
    ),
    TextButton(
      onPressed: _pickValidUntilDate,
      child: const Text('Select Date'),
    ),
  ],
),

              
              // Status
              DropdownButtonFormField<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Paused', child: Text('Paused')),
                  DropdownMenuItem(value: 'Expired', child: Text('Expired')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _status = value;
                    });
                  }
                },
                decoration: const InputDecoration(labelText: 'Status'),
              ),
              
              // Applicable Fuel Types
              const SizedBox(height: 12),
              const Text('Applicable Fuel Types:', style: TextStyle(fontWeight: FontWeight.w500)),
              Wrap(
                children: ['Regular', 'Premium', 'Diesel'].map((fuelType) {
                  final isSelected = _selectedFuelTypes.contains(fuelType);
                  return FilterChip(
                    label: Text(fuelType),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedFuelTypes.add(fuelType);
                        } else {
                          _selectedFuelTypes.remove(fuelType);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              
              // Terms and Conditions
              TextFormField(
                controller: _termsController,
                decoration: const InputDecoration(labelText: 'Terms and Conditions (Optional)'),
                maxLines: 3,
              ),
              
              // Notification Toggle
              SwitchListTile(
                title: const Text('Enable Notifications'),
                subtitle: const Text('Send notifications to users when this voucher is created'),
                value: _isNotificationEnabled,
                onChanged: (value) {
                  setState(() {
                    _isNotificationEnabled = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: Text(widget.voucher == null ? 'Create' : 'Update')),
      ],
    );
  }

  Widget _buildStationDropdown() {
    if (_isLoadingStations) {
      return const CircularProgressIndicator();
    }

    if (_stations.isEmpty) {
      return const Text('No gas stations found for this owner');
    }

    return DropdownButtonFormField<String>(
      value: _selectedStationId,
      decoration: const InputDecoration(
        labelText: 'Select Gas Station',
        border: OutlineInputBorder(),
      ),
      items: _stations.map((station) {
        return DropdownMenuItem(
          value: station['id']?.toString(),
          child: Text(station['name']?.toString() ?? 'Unknown Station'),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedStationId = value;
        });
      },
      validator: (value) => value == null ? 'Please select a gas station' : null,
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const SummaryCard({super.key, required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class OfferFormDialog extends StatefulWidget {
  final Map<String, dynamic>? offer;
  final String ownerId;

  const OfferFormDialog({super.key, this.offer, required this.ownerId});

  @override
  State<OfferFormDialog> createState() => _OfferFormDialogState();
}

class _OfferFormDialogState extends State<OfferFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  DateTime? _validUntil;
  String _status = 'Active';
  String? _selectedStationId;
  List<Map<String, dynamic>> _stations = [];
  bool _isLoadingStations = true;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.offer?['title'] ?? '');
    _descriptionController = TextEditingController(text: widget.offer?['description'] ?? '');
    _validUntil = widget.offer?['validUntil'] != null ? DateTime.parse(widget.offer!['validUntil']) : null;
    _status = widget.offer?['status'] ?? 'Active';
    _selectedStationId = widget.offer?['stationId'];
    _loadStations();
  }

  Future<void> _loadStations() async {
    try {
      final stations = await FirestoreService.getUserAssignedStations(widget.ownerId);
      setState(() {
        _stations = stations;
        _isLoadingStations = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingStations = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickValidUntilDate() async {
    final now = DateTime.now();
    DateTime initialDate = now;
    if (_validUntil != null && _validUntil!.isAfter(now)) {
      initialDate = _validUntil!;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _validUntil = picked;
      });
    }
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    if (_validUntil == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a valid until date')));
      return;
    }
    if (_selectedStationId == null && widget.offer == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a gas station')));
      return;
    }
    
    // Ensure stationId is never empty
    final stationId = _selectedStationId ?? widget.offer?['stationId'];
    if (stationId == null || stationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gas station selection is required')));
      return;
    }
    
    final newOffer = {
      'id': widget.offer?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'validUntil': _validUntil!.toIso8601String(),
      'status': _status,
      'stationId': stationId,
    };
    Navigator.of(context).pop(newOffer);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.offer == null ? 'Create Offer' : 'Edit Offer'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Station selection (only for new offers)
              if (widget.offer == null) ...[
                _buildStationDropdown(),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => value == null || value.isEmpty ? 'Please enter a title' : null,
              ),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (value) => value == null || value.isEmpty ? 'Please enter a description' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Valid Until:'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _validUntil != null ? _validUntil!.toLocal().toString().split(' ')[0] : 'Not set',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _pickValidUntilDate,
                    child: const Text('Select Date'),
                  ),
                ],
              ),

              DropdownButtonFormField<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Paused', child: Text('Paused')),
                  DropdownMenuItem(value: 'Expired', child: Text('Expired')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _status = value;
                    });
                  }
                },
                decoration: const InputDecoration(labelText: 'Status'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: Text(widget.offer == null ? 'Create' : 'Update')),
      ],
    );
  }

  Widget _buildStationDropdown() {
    if (_isLoadingStations) {
      return const CircularProgressIndicator();
    }

    if (_stations.isEmpty) {
      return const Text('No gas stations found for this owner');
    }

    return DropdownButtonFormField<String>(
      value: _selectedStationId,
      decoration: const InputDecoration(
        labelText: 'Select Gas Station',
        border: OutlineInputBorder(),
      ),
      items: _stations.map((station) {
        return DropdownMenuItem(
          value: station['id']?.toString(),
          child: Text(station['name']?.toString() ?? 'Unknown Station'),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedStationId = value;
        });
      },
      validator: (value) => value == null ? 'Please select a gas station' : null,
    );
  }
}