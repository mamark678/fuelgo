import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/price_history.dart';
import '../services/firestore_service.dart';

class GasPriceHistoryScreen extends StatefulWidget {
  const GasPriceHistoryScreen({
    super.key,
    required this.ownerId,
    required this.assignedStations,
  });

  final String ownerId;
  final List<Map<String, dynamic>> assignedStations;

  @override
  State<GasPriceHistoryScreen> createState() => _GasPriceHistoryScreenState();
}

class _GasPriceHistoryScreenState extends State<GasPriceHistoryScreen> {
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy • h:mm a');

  bool _isLoading = true;
  bool _hasError = false;
  List<PriceHistory> _history = [];
  String? _selectedStationId;
  String? _selectedFuelType;
  int? _selectedDaysBack;
  List<String> _availableFuelTypes = [];

  // Convenience getters
  List<Map<String, dynamic>> get _stationOptions => [
        {
          'id': null,
          'name': 'All Stations',
          'brand': '',
        },
        ...widget.assignedStations.map((station) {
          final stationData = Map<String, dynamic>.from(station);
          return {
            'id': stationData['id'] ?? stationData['stationId'],
            'name': stationData['name'] ?? stationData['stationName'] ?? 'Unnamed Station',
            'brand': stationData['brand'] ?? stationData['stationBrand'] ?? '',
          };
        }),
      ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      List<PriceHistory> history = [];

      if (_selectedStationId != null && _selectedStationId!.isNotEmpty) {
        history = await FirestoreService.getPriceHistory(
          stationId: _selectedStationId!,
          fuelType: _selectedFuelType,
          daysBack: _selectedDaysBack,
        );
      } else if (widget.ownerId.isNotEmpty) {
        history = await FirestoreService.getPriceHistoryByOwner(
          ownerId: widget.ownerId,
          fuelType: _selectedFuelType,
          daysBack: _selectedDaysBack,
        );
      }

      if (!mounted) return;

      setState(() {
        _history = history;
        _availableFuelTypes = {
          for (final record in history) record.fuelType
        }.where((fuel) => fuel.isNotEmpty).toList()
          ..sort();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load price history: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _buildStationSubtitle(PriceHistory record) {
    final buffer = <String>[];
    if (record.stationBrand.isNotEmpty) {
      buffer.add(record.stationBrand);
    }
    buffer.add(record.fuelType);
    return buffer.join(' • ');
  }

  Widget _buildFilters() {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filters',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildDropdown<String?>(
                  label: 'Station',
                  value: _selectedStationId,
                  items: _stationOptions.map((station) {
                    final stationId = station['id'] as String?;
                    final name = station['name'] as String? ?? 'Station';
                    final brand = station['brand'] as String? ?? '';
                    final displayName = brand.isNotEmpty ? '$name ($brand)' : name;
                    return DropdownMenuItem<String?>(
                      value: stationId,
                      child: Text(displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedStationId = value;
                    });
                    _loadHistory();
                  },
                ),
                _buildDropdown<String?>(
                  label: 'Fuel Type',
                  value: _selectedFuelType,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Fuel Types'),
                    ),
                    ..._availableFuelTypes.map(
                      (fuel) => DropdownMenuItem<String?>(
                        value: fuel,
                        child: Text(fuel),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedFuelType = value;
                    });
                    _loadHistory();
                  },
                ),
                _buildDropdown<int?>(
                  label: 'Time Range',
                  value: _selectedDaysBack,
                  items: const [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All Time'),
                    ),
                    DropdownMenuItem<int?>(
                      value: 7,
                      child: Text('Last 7 days'),
                    ),
                    DropdownMenuItem<int?>(
                      value: 30,
                      child: Text('Last 30 days'),
                    ),
                    DropdownMenuItem<int?>(
                      value: 90,
                      child: Text('Last 90 days'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedDaysBack = value;
                    });
                    _loadHistory();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 220,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: items.any((item) => item.value == value) ? value : items.first.value,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              'Something went wrong.\nPull to retry.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'No price history found.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Adjust your filters or try again later.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final record = _history[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              child: Icon(
                Icons.local_gas_station,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(record.stationName.isNotEmpty ? record.stationName : 'Station'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_buildStationSubtitle(record)),
                const SizedBox(height: 4),
                Text(_dateFormat.format(record.timestamp)),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '\$${record.price.toStringAsFixed(3)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gas Prices History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildFilters()),
            SliverFillRemaining(
              hasScrollBody: true,
              child: _buildHistoryList(),
            ),
          ],
        ),
      ),
    );
  }
}

