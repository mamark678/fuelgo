import 'package:flutter/material.dart';

import '../models/gas_station.dart';
import '../services/navigation_service.dart';

class NavigationDetailsScreen extends StatefulWidget {
  final GasStation destination;
  final String totalDistance;
  final String totalDuration;
  final String startTime;
  final String endTime;
  final List<RouteStep> routeSteps;

  const NavigationDetailsScreen({
    super.key,
    required this.destination,
    required this.totalDistance,
    required this.totalDuration,
    required this.startTime,
    required this.endTime,
    required this.routeSteps,
  });

  @override
  State<NavigationDetailsScreen> createState() => _NavigationDetailsScreenState();
}

class _NavigationDetailsScreenState extends State<NavigationDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation Summary'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Destination Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Icon(
                            Icons.place,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.destination.name ?? 'Unknown Station',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                widget.destination.brand ?? 'Unknown Brand',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.destination.address ?? 'Address not available',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Navigation Summary
            const Text(
              'Navigation Summary',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Total Distance',
                    widget.totalDistance,
                    Icons.straighten,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Total Duration',
                    widget.totalDuration,
                    Icons.access_time,
                    Colors.green,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Start Time',
                    widget.startTime,
                    Icons.play_arrow,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'End Time',
                    widget.endTime,
                    Icons.stop,
                    Colors.red,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Route Steps
            if (widget.routeSteps.isNotEmpty) ...[
              const Text(
                'Route Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              Card(
                elevation: 2,
                child: Column(
                  children: widget.routeSteps.asMap().entries.map((entry) {
                    final index = entry.key;
                    final step = entry.value;
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        step.instruction,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Row(
                        children: [
                          Icon(Icons.straighten, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            step.distance,
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            step.duration,
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      isThreeLine: false,
                    );
                  }).toList(),
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Navigate back to the station
                      Navigator.of(context).pop();
                      // You could add logic here to navigate back to the station details
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Navigate Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
