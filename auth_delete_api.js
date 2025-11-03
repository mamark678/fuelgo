// Simple Node.js API endpoint for deleting Firebase Auth users
// Deploy this to Vercel, Netlify, or any free Node.js hosting service
// Example: Deploy to Vercel (free tier) - just create vercel.json and deploy

const admin = require('firebase-admin');

// Initialize Firebase Admin (use environment variables for credentials)
if (!admin.apps.length) {
  const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT || '{}');
  
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

exports.handler = async (event, context) => {
  // CORS headers
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };

  // Handle preflight
  if (event.httpMethod === 'OPTIONS') {
    return {
      statusCode: 200,
      headers,
      body: '',
    };
  }

  // Only allow POST
  if (event.httpMethod !== 'POST') {
    return {
      statusCode: 405,
      headers,
      body: JSON.stringify({ error: 'Method not allowed' }),
    };
  }

  try {
    const { userId, adminToken } = JSON.parse(event.body || '{}');

    if (!userId) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: 'userId is required' }),
      };
    }

    // Optional: Verify admin token (if you want additional security)
    // You can verify the token against your admin user's Firebase Auth token
    
    // Delete the user
    await admin.auth().deleteUser(userId);

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({ 
        success: true, 
        message: `User ${userId} deleted successfully` 
      }),
    };
  } catch (error) {
    console.error('Error deleting user:', error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({ 
        error: 'Failed to delete user',
        message: error.message 
      }),
    };
  }
};

