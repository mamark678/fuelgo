import 'package:flutter/material.dart';
import 'package:fuelgo/services/firestore_service.dart';

class StationSelectorWidget extends StatefulWidget {
  final String ownerId;
  final String? selectedStationId;
  final String? selectedFuelType;
  final ValueChanged<String?> onStationChanged;
  final ValueChanged<String?> onFuelTypeChanged;

  const StationSelectorWidget({
    Key? key,
    required this.ownerId,
    required this.selectedStationId,
    required this.selectedFuelType,
    required this.onStationChanged,
    required this.onFuelTypeChanged,
  }) : super(key: key);

  @override
  State<StationSelectorWidget> createState() => _StationSelectorWidgetState();
}

class _StationSelectorWidgetState extends State<StationSelectorWidget> {
  List<Map<String, dynamic>> _stations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    try {
      final stations = await FirestoreService.getGasStationsByOwner(widget.ownerId);
      setState(() {
        _stations = stations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analytics Filters',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildStationDropdown(),
            const SizedBox(height: 12),
            _buildFuelTypeDropdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildStationDropdown() {
    if (_isLoading) {
      return const CircularProgressIndicator();
    }

    if (_stations.isEmpty) {
      return const Text('No stations found');
    }

    return DropdownButtonFormField<String>(
      value: widget.selectedStationId,
      decoration: const InputDecoration(
        labelText: 'Select Station',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('All Stations'),
        ),
        ..._stations.map((station) {
          return DropdownMenuItem(
            value: station['id']?.toString(),
            child: Text(station['name']?.toString() ?? 'Unknown Station'),
          );
        }).toList(),
      ],
      onChanged: widget.onStationChanged,
    );
  }

  Widget _buildFuelTypeDropdown() {
    final fuelTypes = ['regular', 'midgrade', 'premium', 'diesel'];
    
    return DropdownButtonFormField<String>(
      value: widget.selectedFuelType,
      decoration: const InputDecoration(
        labelText: 'Select Fuel Type',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('All Fuel Types'),
        ),
        ...fuelTypes.map((type) {
          return DropdownMenuItem(
            value: type,
            child: Text(type.toUpperCase()),
          );
        }).toList(),
      ],
      onChanged: widget.onFuelTypeChanged,
    );
  }
}
