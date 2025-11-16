class ApiConfig {
  // Replace this with your actual Google Maps API key
  static const String googleMapsApiKey = 'AIzaSyDL2tfnBXHnHq2FkOqPriAsBBTyeoIgf7U';
  
  // GasBuddy-like API endpoints (for future implementation)
  static const String gasPriceApiUrl = 'https://api.example.com/gas-prices';
  
  // Admin Web Portal URL - Update this with your deployed admin portal URL
  // For Firebase Hosting, it would be: https://your-project.web.app/admin-approval
  static const String adminPortalUrl = 'https://your-project.web.app/admin-approval';
  
  // Navigation settings
  static const double defaultZoom = 14.0;
  static const double navigationZoom = 16.0;
  
  // REMOVED: Default location coordinates
  // Application should use user's current location or gas station locations
} 