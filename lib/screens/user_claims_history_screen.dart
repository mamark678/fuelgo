import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class UserClaimsHistoryScreen extends StatefulWidget {
  const UserClaimsHistoryScreen({super.key});

  @override
  State<UserClaimsHistoryScreen> createState() => _UserClaimsHistoryScreenState();
}

class _UserClaimsHistoryScreenState extends State<UserClaimsHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _claimedOffers = [];
  List<Map<String, dynamic>> _redeemedVouchers = [];
  bool _isLoading = true;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserAndClaims();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAndClaims() async {
    final user = AuthService().currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    _userId = user.uid;
    await _loadAllClaims();
  }

  Future<void> _loadAllClaims() async {
    if (_userId == null) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      await Future.wait([
        _loadClaimedOffers(),
        _loadRedeemedVouchers(),
      ]);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load claims: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadClaimedOffers() async {
    if (_userId == null) return;
    try {
      final offers = await FirestoreService.getUserClaimedOffers(_userId!);
      setState(() {
        _claimedOffers = offers;
      });
    } catch (e) {
      print('Error loading claimed offers: $e');
    }
  }

  Future<void> _loadRedeemedVouchers() async {
    if (_userId == null) return;
    try {
      final vouchers = await FirestoreService.getUserRedeemedVouchers(_userId!);
      setState(() {
        _redeemedVouchers = vouchers;
      });
    } catch (e) {
      print('Error loading redeemed vouchers: $e');
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is String) {
      date = DateTime.parse(timestamp);
    } else {
      return 'N/A';
    }
    
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is String) {
      date = DateTime.parse(timestamp);
    } else {
      return 'N/A';
    }
    
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildClaimedOfferCard(Map<String, dynamic> claim) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_offer, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    claim['offerTitle'] ?? 'Unknown Offer',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'CLAIMED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Station: ${claim['stationName'] ?? 'Unknown Station'}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Claimed on: ${_formatDateTime(claim['claimedAt'])}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRedeemedVoucherCard(Map<String, dynamic> voucher) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.confirmation_number, color: Colors.purple, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    voucher['voucherTitle'] ?? 'Unknown Voucher',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'REDEEMED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (voucher['voucherCode'] != null && voucher['voucherCode'].toString().isNotEmpty)
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
                      'Code: ${voucher['voucherCode']}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () => _copyVoucherCode(voucher['voucherCode']),
                      tooltip: 'Copy Code',
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Station ID: ${voucher['stationId'] ?? 'Unknown'}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Redeemed on: ${_formatDateTime(voucher['redeemedAt'])}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyVoucherCode(String code) {
    // This would typically use Clipboard.setData, but for now just show a snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Voucher code copied: $code')),
    );
  }

  Widget _buildEmptyState(String type) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            type == 'offers' ? Icons.local_offer : Icons.confirmation_number,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No $type claimed yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            type == 'offers' 
                ? 'Start claiming offers from gas stations!'
                : 'Start redeeming vouchers from gas stations!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Claims History'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_offer, size: 16),
                  const SizedBox(width: 8),
                  Text('Offers (${_claimedOffers.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.confirmation_number, size: 16),
                  const SizedBox(width: 8),
                  Text('Vouchers (${_redeemedVouchers.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Claimed Offers Tab
          RefreshIndicator(
            onRefresh: _loadClaimedOffers,
            child: _claimedOffers.isEmpty
                ? _buildEmptyState('offers')
                : ListView.builder(
                    itemCount: _claimedOffers.length,
                    itemBuilder: (context, index) {
                      return _buildClaimedOfferCard(_claimedOffers[index]);
                    },
                  ),
          ),
          // Redeemed Vouchers Tab
          RefreshIndicator(
            onRefresh: _loadRedeemedVouchers,
            child: _redeemedVouchers.isEmpty
                ? _buildEmptyState('vouchers')
                : ListView.builder(
                    itemCount: _redeemedVouchers.length,
                    itemBuilder: (context, index) {
                      return _buildRedeemedVoucherCard(_redeemedVouchers[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
