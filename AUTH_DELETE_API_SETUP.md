# Auth User Deletion API Setup

## Overview

This guide helps you set up a free API endpoint to automatically delete Firebase Authentication users when rejecting registrations, without using Cloud Functions (which costs money).

## Option 1: Deploy to Vercel (Recommended - Free Tier)

### Step 1: Create Vercel Project Files

Create these files in your project root:

**vercel.json**:
```json
{
  "version": 2,
  "builds": [
    {
      "src": "auth_delete_api.js",
      "use": "@vercel/node"
    }
  ],
  "routes": [
    {
      "src": "/api/delete-auth-user",
      "dest": "auth_delete_api.js"
    }
  ]
}
```

**package.json** (in project root):
```json
{
  "name": "fuelgo-auth-delete-api",
  "version": "1.0.0",
  "dependencies": {
    "firebase-admin": "^12.6.0"
  }
}
```

### Step 2: Get Firebase Service Account Key

1. Go to Firebase Console → Project Settings → Service Accounts
2. Click "Generate New Private Key"
3. Download the JSON file
4. Copy the JSON content

### Step 3: Deploy to Vercel

1. Install Vercel CLI: `npm i -g vercel`
2. Login: `vercel login`
3. In your project root, run: `vercel`
4. When prompted, set environment variable:
   - Key: `FIREBASE_SERVICE_ACCOUNT`
   - Value: Paste the entire JSON content from Step 2
5. After deployment, copy the URL (e.g., `https://your-project.vercel.app`)

### Step 4: Update API Config

In `lib/config/api_config.dart`, set:
```dart
static const String authDeleteApiUrl = 'https://your-project.vercel.app/api/delete-auth-user';
```

---

## Option 2: Deploy to Netlify (Free Tier)

### Step 1: Create Netlify Function

Create `netlify/functions/delete-auth-user.js` (copy content from `auth_delete_api.js`)

### Step 2: Create netlify.toml

```toml
[build]
  functions = "netlify/functions"

[[redirects]]
  from = "/api/delete-auth-user"
  to = "/.netlify/functions/delete-auth-user"
  status = 200
```

### Step 3: Set Environment Variables

In Netlify Dashboard → Site Settings → Environment Variables:
- Key: `FIREBASE_SERVICE_ACCOUNT`
- Value: JSON content from Firebase Service Account

### Step 4: Deploy

Connect your repo to Netlify or use Netlify CLI:
```bash
npm install -g netlify-cli
netlify login
netlify deploy --prod
```

### Step 5: Update API Config

Set the URL in `lib/config/api_config.dart`:
```dart
static const String authDeleteApiUrl = 'https://your-site.netlify.app/api/delete-auth-user';
```

---

## Option 3: Use Firebase Hosting Functions (Free for low usage)

If you want to use Firebase Hosting, you can deploy a simple Cloud Function:

```bash
cd functions
firebase deploy --only functions:deleteAuthUser
```

Then set the URL in `lib/config/api_config.dart` accordingly.

---

## Security Notes

1. **Service Account Key**: Keep it secure - never commit it to Git
2. **Environment Variables**: Use environment variables for sensitive data
3. **CORS**: The API allows all origins - consider restricting in production
4. **Admin Token Verification**: The API currently accepts any admin token - you may want to add additional verification

## Testing

After deployment:
1. Reject a test user registration
2. Check the console logs for success/failure
3. Verify the Auth user was deleted in Firebase Console → Authentication

## Troubleshooting

### API Not Responding
- Check the API URL in `api_config.dart`
- Verify the endpoint is deployed and accessible
- Check serverless function logs (Vercel/Netlify dashboard)

### Authentication Failed
- Verify `FIREBASE_SERVICE_ACCOUNT` environment variable is set correctly
- Check the JSON format is valid

### User Not Deleted
- Check API endpoint logs for errors
- Verify the userId is correct
- Check Firebase Console → Authentication to see if user exists

