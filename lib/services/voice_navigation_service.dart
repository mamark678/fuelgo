import 'package:flutter_tts/flutter_tts.dart';

class VoiceNavigationService {
  static final VoiceNavigationService _instance = VoiceNavigationService._internal();
  factory VoiceNavigationService() => _instance;
  VoiceNavigationService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isEnabled = true;
  bool _isInitialized = false;

  bool get isEnabled => _isEnabled;

  // Initialize TTS
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5); // Slower speech for navigation
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      
      _isInitialized = true;
    } catch (e) {
      print('Error initializing TTS: $e');
    }
  }

  // Enable/disable voice navigation
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  // Speak navigation instruction
  Future<void> speak(String text) async {
    if (!_isEnabled || !_isInitialized) return;

    try {
      await _flutterTts.speak(text);
    } catch (e) {
      print('Error speaking: $e');
    }
  }

  // Speak turn-by-turn instructions
  void speakTurnInstruction(String instruction) {
    if (!_isEnabled) return;

    // Clean up the instruction for voice
    String cleanInstruction = instruction
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll('Turn ', 'Turn ')
        .replaceAll(' onto ', ' onto ')
        .replaceAll(' toward ', ' toward ')
        .replaceAll(' for ', ' for ');

    speak(cleanInstruction);
  }

  // Speak distance and ETA updates
  void speakDistanceUpdate(String distance, String duration) {
    if (!_isEnabled) return;

    String message = 'Distance remaining: $distance. Estimated time: $duration';
    speak(message);
  }

  // Speak arrival notification
  void speakArrival() {
    if (!_isEnabled) return;

    speak('You have arrived at your destination');
  }

  // Speak route start
  void speakRouteStart(String destination) {
    if (!_isEnabled) return;

    speak('Starting navigation to $destination');
  }

  // Speak route end
  void speakRouteEnd() {
    if (!_isEnabled) return;

    speak('Navigation ended');
  }

  // Stop speaking
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      print('Error stopping TTS: $e');
    }
  }

  // Get available languages
  Future<List<Map<String, String>>> getLanguages() async {
    try {
      final languages = await _flutterTts.getLanguages;
      return languages.cast<Map<String, String>>();
    } catch (e) {
      print('Error getting languages: $e');
      return [];
    }
  }

  // Set language
  Future<void> setLanguage(String languageCode) async {
    try {
      await _flutterTts.setLanguage(languageCode);
    } catch (e) {
      print('Error setting language: $e');
    }
  }

  // Set speech rate
  Future<void> setSpeechRate(double rate) async {
    try {
      await _flutterTts.setSpeechRate(rate);
    } catch (e) {
      print('Error setting speech rate: $e');
    }
  }

  // Set volume
  Future<void> setVolume(double volume) async {
    try {
      await _flutterTts.setVolume(volume);
    } catch (e) {
      print('Error setting volume: $e');
    }
  }

  // Dispose
  void dispose() {
    stop();
  }
} 