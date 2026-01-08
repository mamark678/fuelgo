import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fuelgo/models/analytics_data.dart';
import 'package:fuelgo/services/analytics_service.dart';
import 'package:fuelgo/services/auth_service.dart';
import 'package:fuelgo/services/user_service_fixed.dart';

import 'analytics_screen.dart';
import 'settings_screen.dart';
import 'user_claims_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final List<String> _timePeriods = ['7 days', '30 days', '90 days'];
  String _selectedTimePeriod = '30 days';
  String? _selectedFuelType;
  List<AnalyticsData> _analyticsData = [];
  bool _isLoading = false;
  AnalyticsData? _selectedAnalytics;

  @override
  void initState() {
    super.initState();
    _loadMarketTrendsData();
  }

  Future<void> _loadMarketTrendsData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = AuthService().currentUser;
      if (user != null) {
        final daysBack = _getDaysBackFromPeriod(_selectedTimePeriod);

        final analytics = await AnalyticsService.getMarketTrends(
          fuelType: _selectedFuelType,
          daysBack: daysBack,
        );

        if (mounted) {
          setState(() {
            _analyticsData = analytics;
            if (analytics.isNotEmpty && _selectedAnalytics == null) {
              _selectedAnalytics = analytics.first;
            }
          });
        }
      } else {
        // User is not authenticated, clear analytics data
        if (mounted) {
          setState(() {
            _analyticsData = [];
            _selectedAnalytics = null;
          });
        }
      }
    } catch (e) {
      // Handle error - check if it's a permission denied error
      if (e.toString().contains('PERMISSION_DENIED') ||
          e.toString().contains('Missing or insufficient permissions')) {
        // User is likely logged out, clear analytics data
        if (mounted) {
          setState(() {
            _analyticsData = [];
            _selectedAnalytics = null;
          });
        }
      } else {
        print('Error loading market trends: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  int _getDaysBackFromPeriod(String period) {
    switch (period) {
      case '7 days':
        return 7;
      case '30 days':
        return 30;
      case '90 days':
        return 90;
      default:
        return 30;
    }
  }

  Future<Map<String, dynamic>> _getUserInfo() async {
    final user = AuthService().currentUser;
    if (user == null) {
      return {'name': 'You', 'location': 'Unknown', 'photoBase64': null};
    }

    final profile = await UserServiceFixed.getUserProfile(user.uid);
    final userName =
        profile['name'] ?? await UserServiceFixed.getUserName(user.uid);
    final location = profile['location'] ?? 'Location not specified';
    final photoBase64 = profile['photoBase64'];

    return {
      'name': userName,
      'location': location,
      'photoBase64': photoBase64,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getUserInfo(),
      builder: (context, snap) {
        final name = snap.data?['name'] ?? 'FuelGo User';
        final location = snap.data?['location'] ?? 'Unknown';
        final photoBase64 = snap.data?['photoBase64'];

        return _buildProfileContent(context, name, location, photoBase64);
      },
    );
  }

  Widget _buildProfileContent(
      BuildContext context, String name, String location, String? photoBase64) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor:
                    Theme.of(context).primaryColor.withOpacity(0.1),
                backgroundImage: photoBase64 != null && photoBase64.isNotEmpty
                    ? MemoryImage(base64Decode(photoBase64))
                    : null,
                child: photoBase64 == null || photoBase64.isEmpty
                    ? Icon(
                        Icons.person,
                        size: 50,
                        color: Theme.of(context).primaryColor,
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                location,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Quick Actions
        _buildSectionHeader('Quick Actions'),
        _buildQuickActions(),

        const SizedBox(height: 24),

        const SizedBox(height: 16),

        const SizedBox(height: 24),

        // About App
        _buildAboutSection(),

        const SizedBox(height: 24),

        // Logout Button
        _buildLogoutButton(),
      ],
    );
  }

  Widget _buildTimePeriodSelector() {
    return DropdownButtonFormField<String>(
      value: _selectedTimePeriod,
      decoration: const InputDecoration(
        labelText: 'Time Period',
        border: OutlineInputBorder(),
      ),
      items: _timePeriods.map((period) {
        return DropdownMenuItem(
          value: period,
          child: Text(period),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedTimePeriod = value!;
        });
        _loadMarketTrendsData();
      },
    );
  }

  Widget _buildFuelTypeFilter() {
    return DropdownButtonFormField<String>(
      value: _selectedFuelType,
      decoration: const InputDecoration(
        labelText: 'Fuel Type',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('All Fuel Types'),
        ),
        ...['regular', 'midgrade', 'premium', 'diesel'].map((type) {
          return DropdownMenuItem(
            value: type,
            child: Text(type.toUpperCase()),
          );
        }).toList(),
      ],
      onChanged: (value) {
        setState(() {
          _selectedFuelType = value;
        });
        _loadMarketTrendsData();
      },
    );
  }

  Widget _buildMarketOverview() {
    if (_analyticsData.isEmpty) return const SizedBox();

    final avgPrice = _analyticsData.fold<double>(
            0.0, (sum, data) => sum + data.currentPrice) /
        _analyticsData.length;

    final increasing = _analyticsData.where((d) => d.isPriceIncreasing).length;
    final decreasing = _analyticsData.length - increasing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Market Overview',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMarketStat(
                    'Avg Price', '\$${avgPrice.toStringAsFixed(2)}'),
                _buildMarketStat('Stations', _analyticsData.length.toString()),
                _buildMarketStat('↑ Trends', '$increasing'),
                _buildMarketStat('↓ Trends', '$decreasing'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.history, color: Colors.green),
          title: const Text('My Claims History'),
          subtitle:
              const Text('View your claimed offers and redeemed vouchers'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const UserClaimsHistoryScreen()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.analytics, color: Colors.purple),
          title: const Text('Analytics Dashboard'),
          subtitle: const Text('View detailed price analytics and trends'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AnalyticsScreen()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.settings, color: Colors.blue),
          title: const Text('Settings'),
          subtitle: const Text('Voice navigation, location, and preferences'),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('About FuelGo'),
        ListTile(
          leading: const Icon(Icons.info, color: Colors.green),
          title: const Text('Version'),
          subtitle: const Text('1.0.0'),
        ),
        ListTile(
          leading: const Icon(Icons.location_city, color: Colors.purple),
          title: const Text('Coverage Area'),
          subtitle: const Text('All registered gas stations'),
        ),
        ListTile(
          leading: const Icon(Icons.api, color: Colors.blue),
          title: const Text('API Status'),
          subtitle: const Text('Google Maps APIs - Active'),
        ),
      ],
    );
  }

  Widget _buildLogoutButton() {
    return ListTile(
      leading: const Icon(Icons.logout, color: Colors.red),
      title: const Text('Logout'),
      onTap: () async {
        final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Logout'),
            content: const Text('Are you sure you want to log out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );
        if (shouldLogout == true) {
          await AuthService().signOut();
          if (context.mounted) {
            Navigator.pushNamedAndRemoveUntil(
                context, '/login', (route) => false);
          }
        }
      },
    );
  }
}
