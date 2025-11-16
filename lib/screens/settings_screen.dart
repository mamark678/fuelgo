import 'package:flutter/material.dart';
import '../services/voice_navigation_service.dart';
import '../services/location_tracking_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final VoiceNavigationService _voiceService = VoiceNavigationService();
  final LocationTrackingService _locationService = LocationTrackingService();
  
  bool _voiceEnabled = true;
  bool _highAccuracyLocation = false;
  double _speechRate = 0.5;
  double _volume = 1.0;
  String _selectedLanguage = 'en-US';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _voiceEnabled = _voiceService.isEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Voice Navigation Section
          _buildSectionHeader('Voice Navigation', Icons.volume_up),
          SwitchListTile(
            title: const Text('Enable Voice Guidance'),
            subtitle: const Text('Turn-by-turn voice instructions'),
            value: _voiceEnabled,
            onChanged: (value) {
              setState(() {
                _voiceEnabled = value;
                _voiceService.setEnabled(value);
              });
            },
          ),
          if (_voiceEnabled) ...[
            ListTile(
              title: const Text('Speech Rate'),
              subtitle: Slider(
                value: _speechRate,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                label: _speechRate.toStringAsFixed(1),
                onChanged: (value) {
                  setState(() {
                    _speechRate = value;
                    _voiceService.setSpeechRate(value);
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('Volume'),
              subtitle: Slider(
                value: _volume,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                label: (_volume * 100).round().toString() + '%',
                onChanged: (value) {
                  setState(() {
                    _volume = value;
                    _voiceService.setVolume(value);
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('Language'),
              subtitle: Text(_selectedLanguage),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () => _showLanguageDialog(),
            ),
          ],
          
          const SizedBox(height: 24),
          
          // Location Settings Section
          _buildSectionHeader('Location Settings', Icons.location_on),
          SwitchListTile(
            title: const Text('High Accuracy Mode'),
            subtitle: const Text('More frequent GPS updates for navigation'),
            value: _highAccuracyLocation,
            onChanged: (value) {
              setState(() {
                _highAccuracyLocation = value;
                if (value) {
                  _locationService.enableNavigationMode();
                } else {
                  _locationService.enableNormalMode();
                }
              });
            },
          ),
          
          const SizedBox(height: 24),
          
          // Navigation Features Section
          _buildSectionHeader('Navigation Features', Icons.navigation),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Speed Indicator'),
            subtitle: const Text('Show real-time speed during navigation'),
            trailing: const Icon(Icons.check, color: Colors.green),
          ),
          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('ETA Calculation'),
            subtitle: const Text('Real-time arrival time based on speed'),
            trailing: const Icon(Icons.check, color: Colors.green),
          ),
          ListTile(
            leading: const Icon(Icons.route),
            title: const Text('Turn-by-turn Directions'),
            subtitle: const Text('Detailed step-by-step navigation'),
            trailing: const Icon(Icons.check, color: Colors.green),
          ),
          
          const SizedBox(height: 24),
          
          // About Section
          _buildSectionHeader('About', Icons.info),
          ListTile(
            leading: const Icon(Icons.local_gas_station),
            title: const Text('FuelGo'),
            subtitle: const Text('Gas station finder application'),
          ),
          ListTile(
            leading: const Icon(Icons.location_city),
            title: const Text('Coverage Area'),
            subtitle: const Text('All registered gas stations'),
          ),
          ListTile(
            leading: const Icon(Icons.api),
            title: const Text('API Usage'),
            subtitle: const Text('Google Maps APIs (Free tier)'),
          ),
          
          const SizedBox(height: 24),
          
          // Test Voice Button
          if (_voiceEnabled)
            ElevatedButton.icon(
              onPressed: () {
                _voiceService.speak('Voice navigation is working correctly');
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Test Voice Navigation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Language'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption('English (US)', 'en-US'),
            _buildLanguageOption('English (UK)', 'en-GB'),
            _buildLanguageOption('Spanish', 'es-ES'),
            _buildLanguageOption('French', 'fr-FR'),
            _buildLanguageOption('German', 'de-DE'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption(String name, String code) {
    return ListTile(
      title: Text(name),
      trailing: _selectedLanguage == code 
          ? const Icon(Icons.check, color: Colors.blue)
          : null,
      onTap: () {
        setState(() {
          _selectedLanguage = code;
          _voiceService.setLanguage(code);
        });
        Navigator.pop(context);
      },
    );
  }
} 