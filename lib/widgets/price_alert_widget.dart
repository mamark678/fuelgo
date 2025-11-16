import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/services/firestore_service.dart';

class PriceAlertWidget extends StatefulWidget {
  final String stationId;
  final String stationName;
  final String fuelType;
  final double currentPrice;

  const PriceAlertWidget({
    Key? key,
    required this.stationId,
    required this.stationName,
    required this.fuelType,
    required this.currentPrice,
  }) : super(key: key);

  @override
  State<PriceAlertWidget> createState() => _PriceAlertWidgetState();
}

class _PriceAlertWidgetState extends State<PriceAlertWidget> {
  final TextEditingController _priceController = TextEditingController();
  String _alertType = 'below'; // 'below' or 'above'
  bool _isLoading = false;
  List<Map<String, dynamic>> _activeAlerts = [];
  bool _isLoadingAlerts = true;

  @override
  void initState() {
    super.initState();
    _loadActiveAlerts();
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveAlerts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isLoadingAlerts = false;
        });
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('price_alerts')
          .where('userId', isEqualTo: user.uid)
          .where('stationId', isEqualTo: widget.stationId)
          .where('fuelType', isEqualTo: widget.fuelType)
          .where('isActive', isEqualTo: true)
          .get();

      setState(() {
        _activeAlerts = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
        _isLoadingAlerts = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingAlerts = false;
      });
    }
  }

  Future<void> _createPriceAlert() async {
    final price = double.tryParse(_priceController.text);
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please log in to create price alerts')),
          );
        }
        return;
      }

      // Store alert in price_alerts collection
      await FirebaseFirestore.instance
          .collection('price_alerts')
          .add({
        'userId': user.uid,
        'stationId': widget.stationId,
        'stationName': widget.stationName,
        'fuelType': widget.fuelType,
        'alertType': _alertType,
        'targetPrice': price,
        'currentPrice': widget.currentPrice,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Price alert created! You will be notified when ${widget.fuelType} price goes $_alertType ₱${price.toStringAsFixed(2)}',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _priceController.clear();
        _loadActiveAlerts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating alert: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  'Price Alerts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Get notified when ${widget.fuelType} price at ${widget.stationName} changes',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            
            // Current Price Display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Current Price:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '₱${widget.currentPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Alert Type Selection
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Below'),
                    selected: _alertType == 'below',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _alertType = 'below';
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Above'),
                    selected: _alertType == 'above',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _alertType = 'above';
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Price Input
            TextField(
              controller: _priceController,
              decoration: InputDecoration(
                labelText: 'Target Price (₱)',
                hintText: 'Enter price',
                prefixIcon: const Icon(Icons.attach_money),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            
            // Create Alert Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _createPriceAlert,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_alert),
                label: Text(_isLoading ? 'Creating...' : 'Create Price Alert'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            
            // Active Alerts List
            if (_activeAlerts.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Active Alerts',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ..._activeAlerts.map((alert) => _buildAlertCard(alert)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          alert['alertType'] == 'below' ? Icons.arrow_downward : Icons.arrow_upward,
          color: alert['alertType'] == 'below' ? Colors.green : Colors.red,
        ),
        title: Text(
          '${alert['fuelType']} ${alert['alertType'] == 'below' ? 'below' : 'above'} ₱${alert['targetPrice'].toStringAsFixed(2)}',
        ),
        subtitle: Text(alert['stationName'] ?? ''),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () async {
            try {
              await FirebaseFirestore.instance
                  .collection('price_alerts')
                  .doc(alert['id'])
                  .update({'isActive': false});
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Alert deleted')),
                );
                _loadActiveAlerts();
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error deleting alert: $e')),
                );
              }
            }
          },
        ),
      ),
    );
  }
}

