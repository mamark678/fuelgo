import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/auth_service.dart';
import '../services/firestore_service.dart';
// Import the owner dashboard screen to access the public state
import 'owner_dashboard_screen.dart';

class StationDashboardTab extends StatefulWidget {
  final List<Map<String, dynamic>> assignedStations;
  final String? userId;
  
  const StationDashboardTab({super.key, required this.assignedStations, this.userId});

  @override
  State<StationDashboardTab> createState() => _StationDashboardTabState();
}

class _StationDashboardTabState extends State<StationDashboardTab> {

  int _getTotalFuelTypes() {
    if (widget.assignedStations.isEmpty) return 0;
    final allFuelTypes = <String>{};
    for (final station in widget.assignedStations) {
      final prices = Map<String, dynamic>.from(station['prices'] ?? {});
      allFuelTypes.addAll(prices.keys);
    }
    return allFuelTypes.length;
  }

  double _getAverageRating() {
    if (widget.assignedStations.isEmpty) return 0.0;
    double totalRating = 0.0;
    int count = 0;
    for (final station in widget.assignedStations) {
      final rating = station['rating'] ?? 0.0;
      if (rating > 0) {
        totalRating += rating;
        count++;
      }
    }
    return count > 0 ? totalRating / count : 0.0;
  }

  String _getLastUpdateTime() {
    if (widget.assignedStations.isEmpty) return 'Never';
    DateTime? latestUpdate;
    for (final station in widget.assignedStations) {
      final lastUpdated = station['lastUpdated'];
      if (lastUpdated != null) {
        final updateTime = (lastUpdated as Timestamp).toDate();
        if (latestUpdate == null || updateTime.isAfter(latestUpdate)) {
          latestUpdate = updateTime;
        }
      }
    }
    if (latestUpdate == null) return 'Never';
    
    final now = DateTime.now();
    final difference = now.difference(latestUpdate);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _createTestStation() async {
    try {
      final user = AuthService().currentUser;
      if (user == null) return;
      
      final stationId = 'TEST-${DateTime.now().millisecondsSinceEpoch}';
      await FirestoreService.createOrUpdateGasStation(
        stationId: stationId,
        name: 'Test Gas Station',
        brand: 'Shell',
        position: const LatLng(7.9061, 125.0931), // Valencia City coordinates
        address: 'Test Address, Valencia City, Bukidnon',
        prices: {
          'Regular': 55.50,
          'Premium': 60.00,
          'Diesel': 52.00,
        },
        ownerId: user.uid,
        stationName: 'Test Gas Station',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test station created successfully! Please refresh the dashboard.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating test station: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          // This will trigger the parent's refresh method
          // Now using the public state class
          final parentState = context.findAncestorStateOfType<OwnerDashboardScreenState>();
          if (parentState != null) {
            await parentState.refreshDashboard();
          }
        },
        child: SingleChildScrollView(
        child: Column(
          children: [
            // Station Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color.fromARGB(255, 219, 138, 62), const Color.fromARGB(255, 134, 176, 255)],
                ),
              ),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.assignedStations.isNotEmpty) ...[
                       Row(
                         children: [
                           Container(
                             padding: const EdgeInsets.all(12),
                             decoration: BoxDecoration(
                               color: Colors.white.withOpacity(0.2),
                               borderRadius: BorderRadius.circular(12),
                             ),
                             child: const Icon(
                               Icons.local_gas_station,
                               color: Colors.white,
                               size: 24,
                             ),
                           ),
                           const SizedBox(width: 16),
                           Expanded(
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text(
                                    widget.assignedStations.first['stationName'] ?? 'My Gas Station',
                                   style: const TextStyle(
                                     color: Colors.white,
                                     fontSize: 20,
                                     fontWeight: FontWeight.bold,
                                   ),
                                 ),
                                 const SizedBox(height: 4),
                                 Text(
                                    'ID: #${widget.assignedStations.first['id']}',
                                   style: TextStyle(
                                     color: Colors.white.withOpacity(0.8),
                                     fontSize: 14,
                                   ),
                                 ),
                                 const SizedBox(height: 4),
                                 Row(
                                   children: [
                                     Icon(
                                       Icons.location_on,
                                       color: Colors.white.withOpacity(0.8),
                                       size: 16,
                                     ),
                                     const SizedBox(width: 4),
                                     Text(
                                        widget.assignedStations.first['address'] ?? 'Location not set',
                                       style: TextStyle(
                                         color: Colors.white.withOpacity(0.8),
                                         fontSize: 14,
                                       ),
                                     ),
                                   ],
                                 ),
                               ],
                             ),
                           ),
                         ],
                       ),
                     ] else ...[
                       Row(
                         children: [
                           Container(
                             padding: const EdgeInsets.all(12),
                             decoration: BoxDecoration(
                               color: Colors.white.withOpacity(0.2),
                               borderRadius: BorderRadius.circular(12),
                             ),
                             child: const Icon(
                               Icons.local_gas_station,
                               color: Colors.white,
                               size: 24,
                             ),
                           ),
                           const SizedBox(width: 16),
                           Expanded(
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 const Text(
                                    'No Stations Assigned',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Create a test station to get started',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'User ID: ${widget.userId ?? 'Unknown'}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                               ],
                             ),
                           ),
                         ],
                       ),
                       const SizedBox(height: 16),
                       SizedBox(
                         width: double.infinity,
                         child: ElevatedButton.icon(
                           onPressed: _createTestStation,
                           icon: const Icon(Icons.add),
                           label: const Text('Create Test Station'),
                           style: ElevatedButton.styleFrom(
                             backgroundColor: Colors.white,
                             foregroundColor: Colors.blue.shade800,
                             padding: const EdgeInsets.symmetric(vertical: 12),
                           ),
                         ),
                       ),
                     ],
                  ],
                ),
              ),
            ),
            
            // KPIs Section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Key Performance Indicators',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                    children: [
                       KPICard(
                          title: "Total Stations",
                          value: widget.assignedStations.length.toString(),
                         icon: Icons.local_gas_station,
                         color: Colors.blue,
                         change: widget.assignedStations.isNotEmpty ? "Active" : "None",
                       ),
                       KPICard(
                         title: "Total Fuel Types",
                         value: _getTotalFuelTypes().toString(),
                         icon: Icons.local_gas_station,
                         color: Colors.green,
                         change: "Available",
                       ),
                       KPICard(
                         title: "Average Rating",
                         value: _getAverageRating().toStringAsFixed(1),
                         icon: Icons.star,
                         color: Colors.orange,
                         change: "Stars",
                       ),
                       KPICard(
                         title: "Last Updated",
                         value: _getLastUpdateTime(),
                         icon: Icons.update,
                         color: Colors.yellow.shade700,
                         change: "Recent",
                       ),
                    ],
                  ),
                ],
              ),
            ),

            // Quick Actions Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                         child: QuickActionCard(
                           title: 'Update Prices',
                           subtitle: widget.assignedStations.isNotEmpty ? 'Last: ${_getLastUpdateTime()}' : 'No stations',
                          icon: Icons.local_gas_station,
                          color: Colors.blue,
                      onTap: () {
                             if (widget.assignedStations.isNotEmpty) {
                               // Removed navigation to deleted PriceManagementScreen
                               ScaffoldMessenger.of(context).showSnackBar(
                                 const SnackBar(
                                   content: Text('Manage prices directly in the Prices tab.'),
                                   backgroundColor: Colors.blue,
                                 ),
                               );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('No stations assigned. Create a test station first.'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: QuickActionCard(
                          title: 'Add Promotion',
                          subtitle: '3 active offers',
                          icon: Icons.flash_on,
                          color: Colors.orange,
                          onTap: () {
                            // TODO: Navigate to promotion screen
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            /* Recent Activity Section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ActivityCard(
                    title: 'Price Update',
                    description: 'Regular fuel price changed to ₱55.50',
                    time: '2h ago',
                    icon: Icons.edit,
                  ),
                  const SizedBox(height: 12),
                  ActivityCard(
                    title: 'New Review',
                    description: '5-star review from Juan D.',
                    time: '4h ago',
                    icon: Icons.star,
                  ),
                ],
              ),
            ),*/
          ],
        ),
      ),
      ),
    );
  }
}

class KPICard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String change;

  const KPICard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.change,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  change,
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class QuickActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const QuickActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActivityCard extends StatelessWidget {
  final String title;
  final String description;
  final String time;
  final IconData icon;

  const ActivityCard({
    super.key,
    required this.title,
    required this.description,
    required this.time,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}