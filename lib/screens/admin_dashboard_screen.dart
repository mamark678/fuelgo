import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/admin_analytics_service.dart';
import 'admin_approve_screen.dart';
import 'admin_crud_stations_screen.dart';
import 'admin_crud_users_screen.dart';
import 'admin_crud_offers_vouchers_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _dashboardStats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadDashboardStats();
  }

  Future<void> _loadDashboardStats() async {
    try {
      final stats = await AdminAnalyticsService.getDashboardStats();
      setState(() {
        _dashboardStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading dashboard: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Analytics'),
            Tab(icon: Icon(Icons.pending_actions), text: 'Approvals'),
            Tab(icon: Icon(Icons.local_gas_station), text: 'Stations'),
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.local_offer), text: 'Offers & Vouchers'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _loadDashboardStats();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await AuthService().signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/admin-login');
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAnalyticsTab(),
          const AdminApprovalScreen(),
          const AdminCRUDStationsScreen(),
          const AdminCRUDUsersScreen(),
          const AdminCRUDOffersVouchersScreen(),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_dashboardStats == null) {
      return const Center(child: Text('Failed to load dashboard statistics'));
    }

    final stats = _dashboardStats!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overview Cards
          _buildStatsGrid(stats),
          const SizedBox(height: 24),
          
          // Charts Row
          Row(
            children: [
              Expanded(child: _buildUserRoleChart(stats)),
              const SizedBox(width: 16),
              Expanded(child: _buildApprovalStatusChart(stats)),
            ],
          ),
          const SizedBox(height: 24),
          
          // Station Status Chart
          _buildStationStatusChart(stats),
          const SizedBox(height: 24),
          
          // User Statistics
          _buildSectionTitle('User Statistics'),
          _buildUserStats(stats),
          const SizedBox(height: 24),
          
          // Station Statistics
          _buildSectionTitle('Station Statistics'),
          _buildStationStats(stats),
          const SizedBox(height: 24),
          
          // Offers & Vouchers Statistics
          _buildSectionTitle('Offers & Vouchers'),
          _buildOffersVouchersStats(stats),
          const SizedBox(height: 24),
          
          // Price Statistics
          _buildSectionTitle('Price Statistics'),
          _buildPriceStats(stats),
          const SizedBox(height: 24),
          
          // Recent Activity
          _buildSectionTitle('Recent Activity (Last 7 Days)'),
          _buildRecentActivity(stats),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(Map<String, dynamic> stats) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Total Users',
          '${stats['totalUsers'] ?? 0}',
          Icons.people,
          Colors.blue,
        ),
        _buildStatCard(
          'Total Stations',
          '${stats['totalStations'] ?? 0}',
          Icons.local_gas_station,
          Colors.green,
        ),
        _buildStatCard(
          'Pending Approvals',
          '${stats['pendingApprovals'] ?? 0}',
          Icons.pending_actions,
          Colors.orange,
        ),
        _buildStatCard(
          'Active Offers',
          '${stats['activeOffers'] ?? 0}',
          Icons.local_offer,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
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
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildUserStats(Map<String, dynamic> stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatRow('Total Users', '${stats['totalUsers'] ?? 0}'),
            _buildStatRow('Total Owners', '${stats['totalOwners'] ?? 0}'),
            _buildStatRow('Total Customers', '${stats['totalCustomers'] ?? 0}'),
            const Divider(),
            _buildStatRow('Approved Owners', '${stats['approvedOwners'] ?? 0}', Colors.green),
            _buildStatRow('Pending Approvals', '${stats['pendingApprovals'] ?? 0}', Colors.orange),
            _buildStatRow('Rejected Owners', '${stats['rejectedOwners'] ?? 0}', Colors.red),
            _buildStatRow('Request Resubmission', '${stats['requestSubmission'] ?? 0}', Colors.amber),
          ],
        ),
      ),
    );
  }

  Widget _buildStationStats(Map<String, dynamic> stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatRow('Total Stations', '${stats['totalStations'] ?? 0}'),
            _buildStatRow('Active Stations', '${stats['activeStations'] ?? 0}', Colors.green),
            _buildStatRow('Owner Created', '${stats['ownerCreatedStations'] ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _buildOffersVouchersStats(Map<String, dynamic> stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatRow('Total Offers', '${stats['totalOffers'] ?? 0}'),
            _buildStatRow('Active Offers', '${stats['activeOffers'] ?? 0}', Colors.green),
            const Divider(),
            _buildStatRow('Total Vouchers', '${stats['totalVouchers'] ?? 0}'),
            _buildStatRow('Active Vouchers', '${stats['activeVouchers'] ?? 0}', Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceStats(Map<String, dynamic> stats) {
    final averagePrices = stats['averagePrices'] as Map<String, dynamic>? ?? {};
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatRow('Total Price Updates (30 days)', '${stats['totalPriceUpdates'] ?? 0}'),
            if (averagePrices.isNotEmpty) ...[
              const Divider(),
              const Text('Average Prices:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...averagePrices.entries.map((entry) => 
                _buildStatRow(
                  entry.key,
                  '\$${entry.value.toStringAsFixed(2)}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity(Map<String, dynamic> stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatRow('New Registrations', '${stats['recentRegistrations'] ?? 0}'),
            _buildStatRow('Price Updates', '${stats['recentPriceUpdates'] ?? 0}'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRoleChart(Map<String, dynamic> stats) {
    final totalOwners = stats['totalOwners'] ?? 0;
    final totalCustomers = stats['totalCustomers'] ?? 0;
    final total = totalOwners + totalCustomers;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('User Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: total > 0
                  ? PieChart(
                      PieChartData(
                        sections: [
                          PieChartSectionData(
                            value: totalOwners.toDouble(),
                            title: 'Owners\n$totalOwners',
                            color: Colors.blue,
                            radius: 60,
                          ),
                          PieChartSectionData(
                            value: totalCustomers.toDouble(),
                            title: 'Customers\n$totalCustomers',
                            color: Colors.green,
                            radius: 60,
                          ),
                        ],
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                      ),
                    )
                  : const Center(
                      child: Text('No data available', style: TextStyle(color: Colors.grey)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalStatusChart(Map<String, dynamic> stats) {
    final pending = stats['pendingApprovals'] ?? 0;
    final approved = stats['approvedOwners'] ?? 0;
    final rejected = stats['rejectedOwners'] ?? 0;
    final requestSubmission = stats['requestSubmission'] ?? 0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Owner Approval Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (pending + approved + rejected + requestSubmission) * 1.2,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          switch (value.toInt()) {
                            case 0:
                              return const Text('Pending', style: TextStyle(fontSize: 10));
                            case 1:
                              return const Text('Approved', style: TextStyle(fontSize: 10));
                            case 2:
                              return const Text('Rejected', style: TextStyle(fontSize: 10));
                            case 3:
                              return const Text('Resubmit', style: TextStyle(fontSize: 10));
                            default:
                              return const Text('');
                          }
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: pending.toDouble(),
                          color: Colors.orange,
                          width: 20,
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: approved.toDouble(),
                          color: Colors.green,
                          width: 20,
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 2,
                      barRods: [
                        BarChartRodData(
                          toY: rejected.toDouble(),
                          color: Colors.red,
                          width: 20,
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 3,
                      barRods: [
                        BarChartRodData(
                          toY: requestSubmission.toDouble(),
                          color: Colors.amber,
                          width: 20,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationStatusChart(Map<String, dynamic> stats) {
    final totalStations = stats['totalStations'] ?? 0;
    final activeStations = stats['activeStations'] ?? 0;
    final inactiveStations = totalStations - activeStations;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Station Status Distribution', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: totalStations * 1.2,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          switch (value.toInt()) {
                            case 0:
                              return const Text('Active', style: TextStyle(fontSize: 12));
                            case 1:
                              return const Text('Inactive', style: TextStyle(fontSize: 12));
                            default:
                              return const Text('');
                          }
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: activeStations.toDouble(),
                          color: Colors.green,
                          width: 30,
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: inactiveStations.toDouble(),
                          color: Colors.red,
                          width: 30,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

