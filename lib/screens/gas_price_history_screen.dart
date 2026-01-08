import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/analytics_data.dart';
import '../models/price_history.dart';
import '../services/firestore_service.dart';
import '../widgets/animated_count_text.dart';
import '../widgets/enhanced_price_chart_widget.dart';

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
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  final DateFormat _timeFormat = DateFormat('h:mm a');

  bool _isLoading = true;
  bool _hasError = false;
  List<PriceHistory> _history = [];
  String? _selectedStationId;
  String? _selectedFuelType;
  int? _selectedDaysBack;
  List<String> _availableFuelTypes = [];

  // Convenience getters
  List<Map<String, dynamic>> get _stationOptions =>
      widget.assignedStations.map((station) {
        final stationData = Map<String, dynamic>.from(station);
        return {
          'id': stationData['id'] ?? stationData['stationId'],
          'name': stationData['name'] ??
              stationData['stationName'] ??
              'Unnamed Station',
          'brand': stationData['brand'] ?? stationData['stationBrand'] ?? '',
        };
      }).toList();

  @override
  void initState() {
    super.initState();
    if (widget.assignedStations.isNotEmpty) {
      final firstStation = widget.assignedStations.first;
      _selectedStationId = firstStation['id'] ?? firstStation['stationId'];
    }
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
        // Sorting mostly handled by backend but ensuring here for chart
        _history.sort((a, b) =>
            b.timestamp.compareTo(a.timestamp)); // Newest first for list

        _availableFuelTypes = {for (final record in history) record.fuelType}
            .where((fuel) => fuel.isNotEmpty)
            .toList()
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

  AnalyticsData? _getChartData() {
    if (_history.isEmpty) return null;

    // For the chart, we need oldest to newest
    // And we should probably only show a chart if filtered by station+fuel OR
    // if we can aggregate meaningfully. For now, let's try to show the first station/fuel combo
    // or just all data points if they make sense.

    // If not filtered by station and fuel, the chart might look messy.
    // Let's create an "Average" view or just pick the top series.

    // Simple approach: Transform logic based on filters
    final List<PriceHistory> chartHistory = List.from(_history);

    // If multiple stations or fuels, maybe just show them all (might be chaotic without multi-line support)
    // AnalyticsData supports one series of points.

    // Let's enable chart ONLY when specific station AND specific fuel are selected,
    // OR if we want to show an "average of selected"

    if (_selectedStationId == null || _selectedFuelType == null) {
      // If not specific, maybe don't show chart or show a placeholder?
      // Actually, let's try to show it if we have data, defaulting to the most recent station/fuel
      // to give user something to look at, or an aggregate.

      // Better UX: Show chart only if meaningful.
      if (_selectedStationId != null &&
          _selectedFuelType == null &&
          _availableFuelTypes.isNotEmpty) {
        // Filter for the first available fuel type to show *something*
        final fuel = _availableFuelTypes.first;
        final filtered = chartHistory.where((h) => h.fuelType == fuel).toList();
        if (filtered.isEmpty) return null;
        return AnalyticsData.fromPriceHistory(
          filtered,
          _selectedStationId!,
          filtered.first.stationName,
          fuel,
        );
      }
      return null;
    }

    return AnalyticsData.fromPriceHistory(
      chartHistory,
      _selectedStationId!,
      chartHistory.first.stationName,
      _selectedFuelType!,
    );
  }

  Widget _buildFilters() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_list, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Filter History',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                    final displayName =
                        brand.isNotEmpty ? '$name ($brand)' : name;
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
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 200),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: items.any((item) => item.value == value)
              ? value
              : items.first.value,
          items: items,
          onChanged: onChanged,
          hint: Text(label),
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildEmptyState({String? message, IconData? icon}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.history, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            message ?? 'No price history found.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError) {
      return _buildEmptyState(
          message: 'Something went wrong', icon: Icons.error_outline);
    }

    if (_history.isEmpty) {
      return _buildEmptyState();
    }

    // Calculate changes for list indicators (comparing current index to index+1)
    // _history is sorted Newest -> Oldest

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _history.length,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (context, index) {
        final record = _history[index];
        final nextRecord = (index + 1 < _history.length &&
                _history[index + 1].stationId == record.stationId)
            ? _history[index + 1]
            : null;

        double? priceDiff;
        if (nextRecord != null) {
          priceDiff = record.price - nextRecord.price;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon / Brand
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.local_gas_station,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.stationName.isNotEmpty
                            ? record.stationName
                            : 'Station',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              record.fuelType.toUpperCase(),
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _dateFormat.format(record.timestamp),
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AnimatedCountText(
                      value: record.price,
                      decimalPlaces: 2,
                      prefix: '₱',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (priceDiff != null && priceDiff != 0)
                      Row(
                        children: [
                          Icon(
                            priceDiff > 0
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 12,
                            color: priceDiff > 0 ? Colors.red : Colors.green,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${priceDiff.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: priceDiff > 0 ? Colors.red : Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                  ],
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
    final chartData = _getChartData();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Price History'),
        centerTitle: true,
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
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildFilters()),

            if (chartData != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: EnhancedPriceChartWidget(
                    analyticsData: chartData,
                    chartHeight: 250,
                    showTitle: true,
                  ),
                ),
              ),

            // List Header
            if (_history.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    'History Records',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ),

            SliverToBoxAdapter(child: _buildHistoryList()),
          ],
        ),
      ),
    );
  }
}
