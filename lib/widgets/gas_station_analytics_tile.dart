import 'package:flutter/material.dart';
import 'package:fuelgo/services/user_preferences_service.dart';
import 'package:fuelgo/widgets/animated_count_text.dart';

class GasStationAnalyticsTile extends StatefulWidget {
  final Map<String, dynamic> station;
  final bool isSelected;
  final String? selectedFuelType;
  final double rating;
  final Function(String stationId) onTap;
  final UserPreferencesService prefsService;

  const GasStationAnalyticsTile({
    super.key,
    required this.station,
    required this.isSelected,
    required this.selectedFuelType,
    required this.rating,
    required this.onTap,
    required this.prefsService,
  });

  @override
  State<GasStationAnalyticsTile> createState() =>
      _GasStationAnalyticsTileState();
}

class _GasStationAnalyticsTileState extends State<GasStationAnalyticsTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    );
    _scaleController.value = 1.0;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _scaleController.reverse().then((_) {
      _scaleController.forward();
    });
    final stationId = widget.station['id']?.toString();
    if (stationId != null) {
      widget.onTap(stationId);
    }
  }

  int _getMarkerColor(String brand) {
    switch (brand.toLowerCase()) {
      case 'shell':
        return Colors.red.value;
      case 'petron':
        return Colors.blue.value;
      case 'caltex':
        return Colors.green.value;
      case 'unioil':
        return Colors.orange.value;
      default:
        return Colors.grey.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationId = widget.station['id']?.toString() ?? '';
    final stationName = widget.station['name']?.toString() ?? 'Unknown Station';
    final brand = widget.station['brand']?.toString() ?? '';
    final pricesRaw = widget.station['prices'] as Map<String, dynamic>? ?? {};
    final prices = <String, double>{};
    pricesRaw.forEach((key, value) {
      final normalizedKey = key.toLowerCase();
      final price = (value as num).toDouble();
      if (!prices.containsKey(normalizedKey) ||
          price < prices[normalizedKey]!) {
        prices[normalizedKey] = price;
      }
    });

    final theme = Theme.of(context);
    final markerColor = _getMarkerColor(brand);

    final selectedPrice = (widget.selectedFuelType != null &&
            prices.containsKey(widget.selectedFuelType!.toLowerCase()))
        ? prices[widget.selectedFuelType!.toLowerCase()]!
        : 0.0;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: widget.isSelected ? 8 : 2,
          shadowColor: widget.isSelected
              ? theme.primaryColor.withOpacity(0.4)
              : Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color:
                  widget.isSelected ? theme.primaryColor : Colors.transparent,
              width: widget.isSelected ? 2.0 : 0,
            ),
          ),
          child: InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: widget.isSelected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor.withOpacity(0.08),
                          theme.primaryColor.withOpacity(0.02),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    )
                  : null,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand Avatar
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Color(markerColor).withOpacity(0.2),
                              Color(markerColor).withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: widget.isSelected
                              ? [
                                  BoxShadow(
                                    color: Color(markerColor).withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.transparent,
                          child: Text(
                            (brand.isNotEmpty ? brand[0] : 'G').toUpperCase(),
                            style: TextStyle(
                              color: Color(markerColor),
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stationName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: widget.isSelected
                                    ? theme.primaryColor
                                    : Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Color(markerColor).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          Color(markerColor).withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    brand,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(markerColor),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (widget.rating > 0) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.star,
                                      color: Colors.amber, size: 14),
                                  const SizedBox(width: 2),
                                  Text(
                                    widget.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Status Badge (Simplified - assuming open)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Open',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Price and Actions Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Favorite Button
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            widget.prefsService
                                .toggleFavoriteStation(stationId);
                            setState(() {});
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              widget.prefsService.isFavorite(stationId)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: widget.prefsService.isFavorite(stationId)
                                  ? Colors.red
                                  : Colors.grey[400],
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                      // Price Display
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.green.shade50,
                              Colors.green.shade100,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            const Text(
                              '₱',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(width: 2),
                            selectedPrice > 0
                                ? AnimatedCountText(
                                    value: selectedPrice,
                                    duration:
                                        const Duration(milliseconds: 1000),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  )
                                : const Text(
                                    'N/A',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                            const Text(
                              '/L',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
