import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/voucher_code_service.dart';
import '../services/firestore_service.dart';

class VoucherValidationScreen extends StatefulWidget {
  final String stationId;
  final String stationName;

  const VoucherValidationScreen({
    Key? key,
    required this.stationId,
    required this.stationName,
  }) : super(key: key);

  @override
  State<VoucherValidationScreen> createState() => _VoucherValidationScreenState();
}

class _VoucherValidationScreenState extends State<VoucherValidationScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _isValidating = false;
  Map<String, dynamic>? _validatedVoucher;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _validateVoucherCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a voucher code';
        _validatedVoucher = null;
      });
      return;
    }

    setState(() {
      _isValidating = true;
      _errorMessage = null;
      _validatedVoucher = null;
    });

    try {
      final voucher = await VoucherCodeService.validateVoucherCode(
        code: code,
        stationId: widget.stationId,
      );

      if (voucher != null) {
        setState(() {
          _validatedVoucher = voucher;
          _errorMessage = null;
        });
        
        // Copy code to clipboard
        await Clipboard.setData(ClipboardData(text: code));
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Valid voucher! Code copied to clipboard.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'Invalid or expired voucher code';
          _validatedVoucher = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error validating voucher: $e';
        _validatedVoucher = null;
      });
    } finally {
      setState(() {
        _isValidating = false;
      });
    }
  }

  Future<void> _useVoucher() async {
    if (_validatedVoucher == null) return;

    try {
      // Use the voucher through FirestoreService
      final result = await FirestoreService.useVoucherCode(
        code: _validatedVoucher!['code'],
        stationId: widget.stationId,
        userId: 'staff_user', // In a real app, this would be the actual staff user ID
        userName: 'Staff Member', // In a real app, this would be the actual staff name
      );

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voucher "${_validatedVoucher!['title']}" has been used successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Clear the form
        _codeController.clear();
        setState(() {
          _validatedVoucher = null;
          _errorMessage = null;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error using voucher: ${result['message']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error using voucher: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Validate Voucher - ${widget.stationName}'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter Voucher Code',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            decoration: const InputDecoration(
                              labelText: 'Voucher Code',
                              hintText: 'Enter the voucher code',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.confirmation_number),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => _validateVoucherCode(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isValidating ? null : _validateVoucherCode,
                          icon: _isValidating 
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check),
                          label: Text(_isValidating ? 'Validating...' : 'Validate'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: Colors.red.shade700, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_validatedVoucher != null) ...[
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          const Text(
                            'Valid Voucher',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildVoucherInfo('Title', _validatedVoucher!['title']),
                      _buildVoucherInfo('Code', _validatedVoucher!['code']),
                      _buildVoucherInfo('Discount', _getDiscountDisplay()),
                      _buildVoucherInfo('Valid Until', _formatDate(_validatedVoucher!['validUntil'])),
                      _buildVoucherInfo('Uses Left', '${_validatedVoucher!['maxUses'] - (_validatedVoucher!['used'] ?? 0)}'),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _useVoucher,
                          icon: const Icon(Icons.local_gas_station),
                          label: const Text('Use Voucher'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVoucherInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  String _getDiscountDisplay() {
    final discountType = _validatedVoucher!['discountType'] ?? '';
    final discountValue = _validatedVoucher!['discountValue'] ?? 0.0;
    
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
}
