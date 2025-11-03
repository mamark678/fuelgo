# FuelGo Web Admin Portal

## Overview

The FuelGo application has been configured to publish a **web-only admin portal** that allows administrators to approve, request resubmission, or reject owner registrations. The web version is separate from the mobile app and only exposes admin functionality.

---

## How It Works

### Platform Detection
- **Web**: Automatically shows admin login/approval screens
- **Mobile/Desktop**: Shows full app with customer/owner features

### Web Flow

1. **User visits web URL**
   - System detects web platform (`kIsWeb`)
   - Shows `WebAdminWrapper` which checks authentication
   
2. **Not Logged In**
   - Redirects to `/admin-login`
   - Shows admin login screen
   
3. **Logged In but Not Admin**
   - Verifies user role in Firestore
   - If not admin → Shows error and stays on login screen
   
4. **Logged In as Admin**
   - Automatically redirects to `/admin-approval`
   - Shows pending registrations with approve/reject/resubmission options

---

## Admin Login Screen

**Location**: `lib/screens/admin_login_screen.dart`  
**Route**: `/admin-login`

### Features
- Email/password authentication
- Admin role verification
- Access denied message for non-admin users
- Clean, professional UI optimized for web

### Usage
1. Admin enters email and password
2. System verifies credentials
3. System checks if user has `role: "admin"` in Firestore
4. If admin → Redirects to approval screen
5. If not admin → Shows access denied error

---

## Admin Approval Screen

**Location**: `lib/screens/admin_approve_screen.dart`  
**Route**: `/admin-approval`

### Features
- **Real-time Updates**: Uses StreamBuilder to show pending registrations
- **Three Actions Per Registration**:
  - ✅ **Approve** → Sets status to `approved`, sends approval email
  - 📋 **Request Resubmission** → Sets status to `request_submission`, sends resubmission email
  - ❌ **Reject** → Sets status to `rejected`, sends rejection email
- **Sign Out Button**: Logs out admin and returns to login screen

### Displayed Information
For each pending registration:
- Owner name
- Station name
- Email address
- Submission date
- Action buttons (Approve, Request Resubmission, Reject)

---

## Deployment

### Build for Web

```bash
flutter build web
```

### Deploy to Firebase Hosting

```bash
firebase deploy --only hosting
```

### Deploy to Other Platforms

You can deploy the built web app to:
- Firebase Hosting
- Netlify
- Vercel
- GitHub Pages
- Any static hosting service

The built files will be in `build/web/` directory.

---

## Admin Account Setup

To create an admin account:

1. **Create user in Firebase Auth** (via console or app)
2. **Create user document in Firestore** with:
   ```json
   {
     "role": "admin",
     "email": "admin@example.com",
     "name": "Admin Name"
   }
   ```

### Example Admin User Document

```javascript
// Firestore: users/{userId}
{
  "role": "admin",
  "email": "admin@fuelgo.com",
  "name": "FuelGo Admin",
  "createdAt": [timestamp],
  "emailVerified": true
}
```

---

## Security Considerations

### Firestore Rules
The admin approval screen requires read access to user documents. Ensure your Firestore rules allow admins to:
- Read user documents (already configured in `firestore.rules`)
- Update user documents (admin can update via the screen)

### Authentication
- Admin must be authenticated with Firebase Auth
- Admin must have `role: "admin"` in Firestore
- Non-admin users cannot access admin routes

### Web Routes Protection
- Admin routes (`/admin-login`, `/admin-approval`) are accessible on web
- Mobile app routes are hidden on web platform
- `WebAdminWrapper` enforces admin authentication

---

## Mobile vs Web Comparison

| Feature | Mobile App | Web Portal |
|---------|-----------|------------|
| Customer Features | ✅ | ❌ |
| Owner Sign-up/Login | ✅ | ❌ |
| Owner Dashboard | ✅ | ❌ |
| Admin Approval | ❌ | ✅ |
| Admin Login | ❌ | ✅ |
| Pending Registrations | ❌ | ✅ |

---

## Troubleshooting

### Admin cannot log in
- Check if user exists in Firebase Auth
- Verify `role: "admin"` in Firestore user document
- Check Firestore read permissions for admin user

### Pending registrations not showing
- Verify users have `approvalStatus: "pending"` in Firestore
- Check Firestore read permissions
- Ensure admin has read access to users collection

### Email notifications not sending
- Verify EmailService is configured
- Check Gmail credentials in `lib/screens/admin_approve_screen.dart`
- Ensure EmailJS/Firebase Functions are properly configured

---

## Future Enhancements

Potential improvements:
- Google Sign-In for admin (web)
- Admin dashboard with statistics
- Bulk approval actions
- Filter/search pending registrations
- View submitted documents in browser
- Audit log of approval actions

---

## File Structure

```
lib/
├── main.dart                      # Web platform detection & routing
├── screens/
│   ├── admin_login_screen.dart    # Admin login (web-only)
│   └── admin_approve_screen.dart  # Approval interface
web/
└── index.html                     # Web app entry point
```

---

## Quick Start

1. **Build web app**:
   ```bash
   flutter build web
   ```

2. **Deploy**:
   ```bash
   firebase deploy --only hosting
   ```

3. **Access admin portal**:
   - Visit your Firebase Hosting URL
   - Login with admin credentials
   - Start approving/rejecting registrations!

---

## Support

For issues or questions about the web admin portal, check:
- Firestore rules configuration
- Admin user setup in Firestore
- Email service configuration
- Firebase Hosting deployment logs

