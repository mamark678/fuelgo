import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';

// Fuel Performance Specifications
class FuelPerformanceSpecs {
  static const Map<String, Map<String, dynamic>> gasoline = {
    'standard': {
      'octane_ron_min': 87,
      'octane_ron_max': 91,
      'octane_mon_min': 82,
      'octane_mon_max': 86,
      'posted_octane': 85,
      'ethanol_max': 10,
      'sulfur_ppm': 15,
      'additives': 'Basic detergent package',
      'performance_boost': 0,
    },
    'enhanced': {
      'octane_ron_min': 87,
      'octane_ron_max': 91,
      'octane_mon_min': 82,
      'octane_mon_max': 86,
      'posted_octane': 85,
      'ethanol_max': 10,
      'sulfur_ppm': 15,
      'additives': 'Enhanced detergent + friction modifiers',
      'performance_boost': 3,
    },
    'premium-cleaning': {
      'octane_ron_min': 87,
      'octane_ron_max': 91,
      'octane_mon_min': 82,
      'octane_mon_max': 86,
      'posted_octane': 85,
      'ethanol_max': 10,
      'sulfur_ppm': 15,
      'additives': 'Premium cleaning formula',
      'performance_boost': 5,
    },
    'eco': {
      'octane_ron_min': 87,
      'octane_ron_max': 91,
      'octane_mon_min': 82,
      'octane_mon_max': 86,
      'posted_octane': 85,
      'ethanol_max': 5,
      'sulfur_ppm': 10,
      'additives': 'Eco-friendly additives',
      'performance_boost': 0,
    },
    'high-octane': {
      'octane_ron_min': 95,
      'octane_ron_max': 97,
      'octane_mon_min': 90,
      'octane_mon_max': 92,
      'posted_octane': 93,
      'ethanol_max': 10,
      'sulfur_ppm': 10,
      'additives': 'Anti-knock compounds',
      'performance_boost': 12,
    },
    'ultra-clean': {
      'octane_ron_min': 95,
      'octane_ron_max': 97,
      'octane_mon_min': 90,
      'octane_mon_max': 92,
      'posted_octane': 93,
      'ethanol_max': 10,
      'sulfur_ppm': 10,
      'additives': 'Ultra cleaning technology',
      'performance_boost': 15,
    },
    'performance': {
      'octane_ron_min': 95,
      'octane_ron_max': 97,
      'octane_mon_min': 90,
      'octane_mon_max': 92,
      'posted_octane': 93,
      'ethanol_max': 10,
      'sulfur_ppm': 10,
      'additives': 'Maximum performance formula',
      'performance_boost': 18,
    },
    'racing': {
      'octane_ron_min': 100,
      'octane_ron_max': 116,
      'octane_mon_min': 95,
      'octane_mon_max': 110,
      'posted_octane': 100,
      'ethanol_max': 15,
      'sulfur_ppm': 5,
      'additives': 'Racing fuel compounds',
      'performance_boost': 25,
    },
  };

  static const Map<String, Map<String, dynamic>> diesel = {
    'standard': {
      'cetane_min': 40,
      'cetane_max': 45,
      'sulfur_ppm': 15,
      'bio_content': 0,
      'additives': 'Basic lubricity improvers',
      'performance_boost': 0,
    },
    'high-cetane': {
      'cetane_min': 51,
      'cetane_max': 55,
      'sulfur_ppm': 10,
      'bio_content': 0,
      'additives': 'Cetane improvers + anti-oxidants',
      'performance_boost': 12,
    },
    'ultra-low': {
      'cetane_min': 45,
      'cetane_max': 50,
      'sulfur_ppm': 10,
      'bio_content': 0,
      'additives': 'Ultra-low sulfur content',
      'performance_boost': 5,
    },
    'turbo': {
      'cetane_min': 48,
      'cetane_max': 52,
      'sulfur_ppm': 12,
      'bio_content': 0,
      'additives': 'Turbo diesel formula',
      'performance_boost': 15,
    },
    'bio-blend': {
      'cetane_min': 48,
      'cetane_max': 52,
      'sulfur_ppm': 12,
      'bio_content': 20,
      'additives': 'Bio-stability improvers',
      'performance_boost': 5,
    },
  };
}
class ManagePricesScreen extends StatefulWidget {
  final Map<String, dynamic> station;

  const ManagePricesScreen({
    super.key,
    required this.station,
  });

  @override
  State<ManagePricesScreen> createState() => _ManagePricesScreenState();
}

class _ManagePricesScreenState extends State<ManagePricesScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers for price inputs
  final _regularPriceController = TextEditingController();
  final _midgradePriceController = TextEditingController();
  final _premiumPriceController = TextEditingController();
  final _dieselPriceController = TextEditingController();

  // Controllers for performance metrics
  // Regular Gasoline
  final _regularOctaneController = TextEditingController();
  final _regularEthanolController = TextEditingController();
  final _regularSulfurController = TextEditingController();

  // Midgrade Gasoline
  final _midgradeOctaneController = TextEditingController();
  final _midgradeEthanolController = TextEditingController();
  final _midgradeSulfurController = TextEditingController();

  // Premium Gasoline
  final _premiumOctaneController = TextEditingController();
  final _premiumEthanolController = TextEditingController();
  final _premiumSulfurController = TextEditingController();

  // Diesel
  final _dieselCetaneController = TextEditingController();
  final _dieselSulfurController = TextEditingController();
  
  // Performance type selections
  String? _regularPerformance;
  String? _midgradePerformance;
  String? _premiumPerformance;
  String? _dieselPerformance;

  // Current prices from station data
  late Map<String, dynamic> currentPrices;
  bool _isLoading = false;
  StreamSubscription<DocumentSnapshot>? _priceListener;

  @override
  void initState() {
    super.initState();
    currentPrices = Map<String, dynamic>.from(widget.station['prices'] ?? {});
    _loadCurrentPrices();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _regularPriceController.dispose();
    _midgradePriceController.dispose();
    _premiumPriceController.dispose();
    _dieselPriceController.dispose();

    // Dispose performance controllers
    _regularOctaneController.dispose();
    _regularEthanolController.dispose();
    _regularSulfurController.dispose();

    _midgradeOctaneController.dispose();
    _midgradeEthanolController.dispose();
    _midgradeSulfurController.dispose();

    _premiumOctaneController.dispose();
    _premiumEthanolController.dispose();
    _premiumSulfurController.dispose();

    _dieselCetaneController.dispose();
    _dieselSulfurController.dispose();

    _priceListener?.cancel();
    super.dispose();
  }

  void _loadCurrentPrices() {
    setState(() {
      _regularPriceController.text = currentPrices['regular']?.toString() ?? '';
      _midgradePriceController.text = currentPrices['midgrade']?.toString() ?? '';
      _premiumPriceController.text = currentPrices['premium']?.toString() ?? '';
      _dieselPriceController.text = currentPrices['diesel']?.toString() ?? '';
    });
  }

  void _setupRealtimeListener() {
    _priceListener = FirebaseFirestore.instance
        .collection('gas_stations')
        .doc(widget.station['id'])
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return; // Check if widget is still mounted
      
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null && data['prices'] != null) {
          setState(() {
            currentPrices = Map<String, dynamic>.from(data['prices']);
            _loadCurrentPrices();
          });
        }
      }
    });
  }

  Future<void> _updatePricesInFirestore() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => _isLoading = true);

  try {
    final updates = <String, double>{};
    final performanceUpdates = <String, Map<String, dynamic>>{};
    
    // Only include prices that are being updated
    if (_regularPriceController.text.isNotEmpty) {
      updates['regular'] = double.parse(_regularPriceController.text);
    }
    if (_midgradePriceController.text.isNotEmpty) {
      updates['midgrade'] = double.parse(_midgradePriceController.text);
    }
    if (_premiumPriceController.text.isNotEmpty) {
      updates['premium'] = double.parse(_premiumPriceController.text);
    }
    if (_dieselPriceController.text.isNotEmpty) {
      updates['diesel'] = double.parse(_dieselPriceController.text);
    }

    // Add performance data with metrics
    if (_regularPerformance != null || _regularOctaneController.text.isNotEmpty || _regularEthanolController.text.isNotEmpty || _regularSulfurController.text.isNotEmpty) {
      performanceUpdates['regular'] = {
        'type': _regularPerformance,
        'label': _getPerformanceLabel(_regularPerformance ?? ''),
        'description': _getPerformanceDescription(_regularPerformance ?? ''),
        'metrics': {
          if (_regularOctaneController.text.isNotEmpty) 'octane': double.tryParse(_regularOctaneController.text),
          if (_regularEthanolController.text.isNotEmpty) 'ethanol_content': double.tryParse(_regularEthanolController.text),
          if (_regularSulfurController.text.isNotEmpty) 'sulfur_content': double.tryParse(_regularSulfurController.text),
        },
      };
    }
    if (_midgradePerformance != null || _midgradeOctaneController.text.isNotEmpty || _midgradeEthanolController.text.isNotEmpty || _midgradeSulfurController.text.isNotEmpty) {
      performanceUpdates['midgrade'] = {
        'type': _midgradePerformance,
        'label': _getPerformanceLabel(_midgradePerformance ?? ''),
        'description': _getPerformanceDescription(_midgradePerformance ?? ''),
        'metrics': {
          if (_midgradeOctaneController.text.isNotEmpty) 'octane': double.tryParse(_midgradeOctaneController.text),
          if (_midgradeEthanolController.text.isNotEmpty) 'ethanol_content': double.tryParse(_midgradeEthanolController.text),
          if (_midgradeSulfurController.text.isNotEmpty) 'sulfur_content': double.tryParse(_midgradeSulfurController.text),
        },
      };
    }
    if (_premiumPerformance != null || _premiumOctaneController.text.isNotEmpty || _premiumEthanolController.text.isNotEmpty || _premiumSulfurController.text.isNotEmpty) {
      performanceUpdates['premium'] = {
        'type': _premiumPerformance,
        'label': _getPerformanceLabel(_premiumPerformance ?? ''),
        'description': _getPerformanceDescription(_premiumPerformance ?? ''),
        'metrics': {
          if (_premiumOctaneController.text.isNotEmpty) 'octane': double.tryParse(_premiumOctaneController.text),
          if (_premiumEthanolController.text.isNotEmpty) 'ethanol_content': double.tryParse(_premiumEthanolController.text),
          if (_premiumSulfurController.text.isNotEmpty) 'sulfur_content': double.tryParse(_premiumSulfurController.text),
        },
      };
    }
    if (_dieselPerformance != null || _dieselCetaneController.text.isNotEmpty || _dieselSulfurController.text.isNotEmpty) {
      performanceUpdates['diesel'] = {
        'type': _dieselPerformance,
        'label': _getPerformanceLabel(_dieselPerformance ?? ''),
        'description': _getPerformanceDescription(_dieselPerformance ?? ''),
        'metrics': {
          if (_dieselCetaneController.text.isNotEmpty) 'cetane_number': double.tryParse(_dieselCetaneController.text),
          if (_dieselSulfurController.text.isNotEmpty) 'sulfur_content': double.tryParse(_dieselSulfurController.text),
        },
      };
    }

    if (updates.isEmpty && performanceUpdates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please make at least one change')),
      );
      return;
    }

    // Create the complete price map for history recording
    // This should include ALL current prices (updated + existing)
    final completeCurrentPrices = <String, double>{};
    
    // Add existing prices
    for (final entry in currentPrices.entries) {
      if (entry.value is num) {
        completeCurrentPrices[entry.key] = (entry.value as num).toDouble();
      }
    }
    
    // Override with any updates
    completeCurrentPrices.addAll(updates);

    // First update the station document with ALL current prices (analytics needs complete data)
    if (updates.isNotEmpty || performanceUpdates.isNotEmpty) {
      await FirestoreService.updateGasStationPricesAndPerformance(
        stationId: widget.station['id'],
        prices: completeCurrentPrices, // ALL current prices for analytics
        fuelPerformance: performanceUpdates,
      );
    }

    // Then record price history with ALL current prices (so analytics has complete data)
    if (updates.isNotEmpty) {
      await FirestoreService.recordPriceChange(
        stationId: widget.station['id'],
        stationName: widget.station['stationName'] ?? widget.station['name'] ?? 'Unknown Station',
        stationBrand: widget.station['brand'] ?? 'Unknown Brand',
        prices: completeCurrentPrices, // ALL prices for consistent history
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Prices and performance updated successfully!'),
        backgroundColor: Colors.green,
      ),
    );
    } catch (e) {
      print('DEBUG: Error updating prices: $e');
      print('DEBUG: Stack trace: ${e.toString()}');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating prices: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
}

  String _getPerformanceLabel(String value) {
    const performanceOptions = {
      'standard': 'Standard',
      'enhanced': 'Enhanced',
      'premium-cleaning': 'Premium Cleaning',
      'eco': 'Eco-Friendly',
      'high-octane': 'High Octane',
      'ultra-clean': 'Ultra Clean',
      'performance': 'Maximum Performance',
      'racing': 'Racing Grade',
      'high-cetane': 'High Cetane',
      'ultra-low': 'Ultra-Low Sulfur',
      'turbo': 'Turbo Formula',
      'bio-blend': 'Bio Blend',
    };
    return performanceOptions[value] ?? value;
  }

  String _getPerformanceDescription(String value) {
    const descriptions = {
      'standard': 'Standard fuel with basic additives for everyday use',
      'enhanced': 'Enhanced detergency for better engine cleanliness',
      'premium-cleaning': 'Premium cleaning formula for superior engine protection',
      'eco': 'Eco-friendly blend with reduced emissions',
      'high-octane': 'High octane rating for improved performance',
      'ultra-clean': 'Ultra cleaning technology for maximum engine protection',
      'performance': 'Maximum performance formula for demanding applications',
      'racing': 'Racing grade fuel for high-performance engines',
      'high-cetane': 'High cetane rating for better diesel combustion',
      'ultra-low': 'Ultra-low sulfur content for cleaner emissions',
      'turbo': 'Turbo diesel formula for enhanced power delivery',
      'bio-blend': 'Biodiesel blend supporting renewable energy',
    };
    return descriptions[value] ?? 'Performance fuel type';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCurrentPricesSection(),
                      const SizedBox(height: 24),
                      _buildUpdatePricesSection(),
                    ],
                  ),
                ),
              ),
            ),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPricesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current Prices',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        if (currentPrices.isNotEmpty) ...[
          ...currentPrices.entries.map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entry.key == 'regular' ? 'Regular Gasoline' :
                    entry.key == 'midgrade' ? 'Midgrade Gasoline' :
                    entry.key == 'premium' ? 'Premium Gasoline' :
                    entry.key == 'diesel' ? 'Diesel' : entry.key,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '₱${entry.value.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ] else ...[
          const Text(
            'No prices set',
            style: TextStyle(
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUpdatePricesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Update Prices & Performance',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter new prices and select performance type for each fuel.\nLeave empty to keep current price.',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        
        // Regular Gasoline
        _buildFuelCard(
          title: 'Regular Gasoline',
          priceController: _regularPriceController,
          currentValue: currentPrices['regular']?.toString() ?? '55.50',
          performanceValue: _regularPerformance,
          performanceOptions: const [
            {'value': 'standard', 'label': 'Standard (RON 87-91)'},
            {'value': 'enhanced', 'label': 'Enhanced Detergency'},
            {'value': 'premium-cleaning', 'label': 'Premium Cleaning Formula'},
            {'value': 'eco', 'label': 'Eco-Friendly Blend'},
          ],
          onPerformanceChanged: (value) {
            setState(() {
              _regularPerformance = value;
            });
          },
          fuelType: 'gasoline',
          performanceMetrics: [
            {'label': 'Octane', 'controller': _regularOctaneController, 'hint': 'e.g. 87'},
            {'label': 'Ethanol Content (%)', 'controller': _regularEthanolController, 'hint': 'e.g. 10'},
            {'label': 'Sulfur Content (ppm)', 'controller': _regularSulfurController, 'hint': 'e.g. 15'},
          ],
        ),

        const SizedBox(height: 16),

        // Midgrade Gasoline
        _buildFuelCard(
          title: 'Midgrade Gasoline',
          priceController: _midgradePriceController,
          currentValue: currentPrices['midgrade']?.toString() ?? '58.00',
          performanceValue: _midgradePerformance,
          performanceOptions: const [
            {'value': 'standard', 'label': 'Standard (RON 89-92)'},
            {'value': 'enhanced', 'label': 'Enhanced Detergency'},
            {'value': 'premium-cleaning', 'label': 'Premium Cleaning Formula'},
            {'value': 'eco', 'label': 'Eco-Friendly Blend'},
          ],
          onPerformanceChanged: (value) {
            setState(() {
              _midgradePerformance = value;
            });
          },
          fuelType: 'gasoline',
          performanceMetrics: [
            {'label': 'Octane', 'controller': _midgradeOctaneController, 'hint': 'e.g. 89'},
            {'label': 'Ethanol Content (%)', 'controller': _midgradeEthanolController, 'hint': 'e.g. 10'},
            {'label': 'Sulfur Content (ppm)', 'controller': _midgradeSulfurController, 'hint': 'e.g. 15'},
          ],
        ),

        const SizedBox(height: 16),

        // Premium Gasoline
        _buildFuelCard(
          title: 'Premium Gasoline',
          priceController: _premiumPriceController,
          currentValue: currentPrices['premium']?.toString() ?? '61.21',
          performanceValue: _premiumPerformance,
          performanceOptions: const [
            {'value': 'high-octane', 'label': 'High Octane (RON 95-97)'},
            {'value': 'ultra-clean', 'label': 'Ultra Cleaning Technology'},
            {'value': 'performance', 'label': 'Maximum Performance'},
            {'value': 'racing', 'label': 'Racing Grade (RON 100+)'},
          ],
          onPerformanceChanged: (value) {
            setState(() {
              _premiumPerformance = value;
            });
          },
          fuelType: 'gasoline',
          performanceMetrics: [
            {'label': 'Octane', 'controller': _premiumOctaneController, 'hint': 'e.g. 95'},
            {'label': 'Ethanol Content (%)', 'controller': _premiumEthanolController, 'hint': 'e.g. 10'},
            {'label': 'Sulfur Content (ppm)', 'controller': _premiumSulfurController, 'hint': 'e.g. 15'},
          ],
        ),

        const SizedBox(height: 16),

        // Diesel
        _buildFuelCard(
          title: 'Diesel',
          priceController: _dieselPriceController,
          currentValue: currentPrices['diesel']?.toString() ?? '52.00',
          performanceValue: _dieselPerformance,
          performanceOptions: const [
            {'value': 'standard', 'label': 'Standard Diesel'},
            {'value': 'high-cetane', 'label': 'High Cetane (CN 51+)'},
            {'value': 'ultra-low', 'label': 'Ultra-Low Sulfur'},
            {'value': 'turbo', 'label': 'Turbo Diesel Formula'},
            {'value': 'bio-blend', 'label': 'Biodiesel Blend (B5-B20)'},
          ],
          onPerformanceChanged: (value) {
            setState(() {
              _dieselPerformance = value;
            });
          },
          fuelType: 'diesel',
          performanceMetrics: [
            {'label': 'Cetane Number (CN)', 'controller': _dieselCetaneController, 'hint': 'e.g. 45'},
            {'label': 'Sulfur Content (ppm)', 'controller': _dieselSulfurController, 'hint': 'e.g. 15'},
          ],
        ),
      ],
    );
  }

  Widget _buildFuelCard({
    required String title,
    required TextEditingController priceController,
    required String currentValue,
    required String? performanceValue,
    required List<Map<String, String>> performanceOptions,
    required ValueChanged<String?> onPerformanceChanged,
    required String fuelType,
    required List<Map<String, dynamic>> performanceMetrics,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 20),

          // Price Input (same as before)
          _buildPriceInput(priceController, currentValue),

          const SizedBox(height: 20),

          // Performance Type Selection
          _buildPerformanceDropdown(
            performanceValue,
            performanceOptions,
            onPerformanceChanged
          ),

          // Auto-populated Performance Specs Display
          if (performanceValue != null) ...[
            const SizedBox(height: 16),
            _buildPerformanceSpecsDisplay(performanceValue, fuelType),
          ],

          // Performance Metrics Inputs
          if (performanceValue != null && performanceMetrics.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildPerformanceMetricsInputs(performanceMetrics),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceInput(TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Price (₱)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: TextFormField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(4),
              ),
              child: IconButton(
                icon: Icon(Icons.refresh, color: Colors.grey[600], size: 20),
                onPressed: () {
                  controller.clear();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPerformanceDropdown(
    String? value,
    List<Map<String, String>> options,
    ValueChanged<String?> onChanged
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Performance Type',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: DropdownButtonFormField<String>(
            value: value,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
            ),
            hint: Text(
              'Select Performance Type',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 15,
              ),
            ),
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 15,
            ),
            dropdownColor: Colors.white,
            items: options.map((option) {
              return DropdownMenuItem(
                value: option['value'],
                child: Text(option['label']!),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceSpecsDisplay(String performanceType, String fuelType) {
    final specs = fuelType == 'diesel'
        ? FuelPerformanceSpecs.diesel[performanceType]
        : FuelPerformanceSpecs.gasoline[performanceType];

    if (specs == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance Specifications',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(height: 8),

          if (fuelType == 'diesel') ...[
            _buildSpecRow('Cetane Number', '${specs['cetane_min']}-${specs['cetane_max']} CN'),
            _buildSpecRow('Sulfur Content', '${specs['sulfur_ppm']} ppm'),
            if (specs['bio_content'] > 0)
              _buildSpecRow('Bio Content', 'B${specs['bio_content']}'),
          ] else ...[
            _buildSpecRow('RON Range', '${specs['octane_ron_min']}-${specs['octane_ron_max']}'),
            _buildSpecRow('MON Range', '${specs['octane_mon_min']}-${specs['octane_mon_max']}'),
            _buildSpecRow('Posted Octane', '${specs['posted_octane']}'),
            _buildSpecRow('Max Ethanol', '${specs['ethanol_max']}%'),
            _buildSpecRow('Sulfur Content', '${specs['sulfur_ppm']} ppm'),
          ],

          if (specs['performance_boost'] > 0)
            _buildSpecRow('Performance Boost', '+${specs['performance_boost']}%'),

          const SizedBox(height: 6),
          Text(
            specs['additives'],
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Performance Metrics Inputs
  Widget _buildPerformanceMetricsInputs(List<Map<String, dynamic>> metrics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance Metrics',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        ...metrics.map((metric) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    metric['label'],
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: TextFormField(
                      controller: metric['controller'],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: metric['hint'],
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildCustomInput(String label, String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: TextFormField(
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _resetToCurrentPrices,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue.shade600,
                side: BorderSide(color: Colors.blue.shade600, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                'Reset to Current',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _updatePricesInFirestore,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Update Prices',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _resetToCurrentPrices() {
    setState(() {
      _regularPriceController.clear();
      _midgradePriceController.clear();
      _premiumPriceController.clear();
      _dieselPriceController.clear();

      // Clear performance controllers
      _regularOctaneController.clear();
      _regularEthanolController.clear();
      _regularSulfurController.clear();

      _midgradeOctaneController.clear();
      _midgradeEthanolController.clear();
      _midgradeSulfurController.clear();

      _premiumOctaneController.clear();
      _premiumEthanolController.clear();
      _premiumSulfurController.clear();

      _dieselCetaneController.clear();
      _dieselSulfurController.clear();

      _regularPerformance = null;
      _midgradePerformance = null;
      _premiumPerformance = null;
      _dieselPerformance = null;
    });
  }
}