import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class AdminCRUDOffersVouchersScreen extends StatefulWidget {
  const AdminCRUDOffersVouchersScreen({Key? key}) : super(key: key);

  @override
  State<AdminCRUDOffersVouchersScreen> createState() => _AdminCRUDOffersVouchersScreenState();
}

class _AdminCRUDOffersVouchersScreenState extends State<AdminCRUDOffersVouchersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _offers = [];
  List<Map<String, dynamic>> _vouchers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final stations = await FirestoreService.getAllGasStations();
      
      final offers = <Map<String, dynamic>>[];
      final vouchers = <Map<String, dynamic>>[];
      
      for (final station in stations) {
        final stationId = station['id'] as String;
        final stationName = station['name'] as String? ?? 'Unknown';
        
        // Get offers
        final stationOffers = List<Map<String, dynamic>>.from(station['offers'] ?? []);
        for (final offer in stationOffers) {
          final offerWithStation = Map<String, dynamic>.from(offer);
          offerWithStation['stationId'] = stationId;
          offerWithStation['stationName'] = stationName;
          offers.add(offerWithStation);
        }
        
        // Get vouchers
        final stationVouchers = List<Map<String, dynamic>>.from(station['vouchers'] ?? []);
        for (final voucher in stationVouchers) {
          final voucherWithStation = Map<String, dynamic>.from(voucher);
          voucherWithStation['stationId'] = stationId;
          voucherWithStation['stationName'] = stationName;
          vouchers.add(voucherWithStation);
        }
      }
      
      setState(() {
        _offers = offers;
        _vouchers = vouchers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredOffers {
    if (_searchQuery.isEmpty) return _offers;
    final query = _searchQuery.toLowerCase();
    return _offers.where((offer) {
      final title = (offer['title'] ?? '').toString().toLowerCase();
      final description = (offer['description'] ?? '').toString().toLowerCase();
      final stationName = (offer['stationName'] ?? '').toString().toLowerCase();
      return title.contains(query) || description.contains(query) || stationName.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredVouchers {
    if (_searchQuery.isEmpty) return _vouchers;
    final query = _searchQuery.toLowerCase();
    return _vouchers.where((voucher) {
      final title = (voucher['title'] ?? '').toString().toLowerCase();
      final description = (voucher['description'] ?? '').toString().toLowerCase();
      final stationName = (voucher['stationName'] ?? '').toString().toLowerCase();
      return title.contains(query) || description.contains(query) || stationName.contains(query);
    }).toList();
  }

  Future<void> _deleteOffer(String stationId, Map<String, dynamic> offer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Offer'),
        content: Text('Are you sure you want to delete offer "${offer['title'] ?? 'Unknown'}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirestoreService.deleteOffer(stationId: stationId, offer: offer);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offer deleted successfully')),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting offer: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteVoucher(String stationId, Map<String, dynamic> voucher) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Voucher'),
        content: Text('Are you sure you want to delete voucher "${voucher['title'] ?? 'Unknown'}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirestoreService.deleteVoucher(stationId: stationId, voucher: voucher);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voucher deleted successfully')),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting voucher: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              labelText: 'Search offers/vouchers',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        
        // Tabs
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Offers', icon: Icon(Icons.local_offer)),
            Tab(text: 'Vouchers', icon: Icon(Icons.card_giftcard)),
          ],
        ),
        
        // Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOffersList(),
              _buildVouchersList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOffersList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredOffers.isEmpty) {
      return const Center(child: Text('No offers found'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filteredOffers.length,
        itemBuilder: (context, index) {
          final offer = _filteredOffers[index];
          final status = offer['status'] as String? ?? 'Active';
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(offer['title'] ?? 'Unknown'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer['description'] ?? ''),
                  Text('Station: ${offer['stationName'] ?? 'Unknown'}'),
                  Text('Status: $status'),
                  if (offer['used'] != null && offer['maxUses'] != null)
                    Text('Used: ${offer['used']}/${offer['maxUses']}'),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteOffer(
                  offer['stationId'] ?? '',
                  offer,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVouchersList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredVouchers.isEmpty) {
      return const Center(child: Text('No vouchers found'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filteredVouchers.length,
        itemBuilder: (context, index) {
          final voucher = _filteredVouchers[index];
          final status = voucher['status'] as String? ?? 'Active';
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(voucher['title'] ?? 'Unknown'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(voucher['description'] ?? ''),
                  Text('Station: ${voucher['stationName'] ?? 'Unknown'}'),
                  Text('Status: $status'),
                  if (voucher['code'] != null)
                    Text('Code: ${voucher['code']}'),
                  if (voucher['used'] != null && voucher['maxUses'] != null)
                    Text('Used: ${voucher['used']}/${voucher['maxUses']}'),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteVoucher(
                  voucher['stationId'] ?? '',
                  voucher,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

