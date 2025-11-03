class ApiConfig {
  // Replace this with your actual Google Maps API key
  static const String googleMapsApiKey = 'AIzaSyDL2tfnBXHnHq2FkOqPriAsBBTyeoIgf7U';
  
  // GasBuddy-like API endpoints (for future implementation)
  static const String gasPriceApiUrl = 'https://api.example.com/gas-prices';
  
  // Admin Web Portal URL - Update this with your deployed admin portal URL
  // For Firebase Hosting, it would be: https://your-project.web.app/admin-approval
  static const String adminPortalUrl = 'https://your-project.web.app/admin-approval';
  
  // Auth User Deletion API Endpoint
  // Deploy auth_delete_api.js to a free hosting service (Vercel, Netlify, etc.)
  // Example: https://your-api.vercel.app/api/delete-auth-user
  // Leave empty to skip Auth user deletion
  static const String authDeleteApiUrl = ''; // Set this to your deployed API URL
  
  // Navigation settings
  static const double defaultZoom = 14.0;
  static const double navigationZoom = 16.0;
  
  // Valencia City, Bukidnon coordinates
  static const double valenciaLatitude = 7.9061;
  static const double valenciaLongitude = 125.0936;
} 