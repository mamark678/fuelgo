# Ways to Trigger Approval Status Changes

## Overview
There are **3 main ways** for admins to change a user's approval status from `pending` to either `approved`, `request_submission`, or `rejected`:

---

## Method 1: Admin Approval Screen (Primary Method)

### Location
- **File**: `lib/screens/admin_approve_screen.dart`
- **Route**: `/admin-approval` (accessible to admin users)

### How It Works
1. Admin opens the Admin Approval Screen
2. Screen displays all users with `approvalStatus: "pending"`
3. For each pending user, admin sees:
   - User name and email
   - Station name
   - Submission date
   - **Three action buttons:**
     - ✅ **Approve** (Green button)
     - 📋 **Request Resubmission** (Orange button)
     - ❌ **Reject** (Red button)

### Actions Available

#### 1. Approve
- **Button**: Green "Approve" button
- **Status Change**: `pending` → `approved`
- **Additional Updates**:
  - Sets `documentsSubmitted: true`
  - Sets `approvedAt: [timestamp]`
  - Sets `emailNotificationSent: true`
- **Email Sent**: Approval confirmation email to owner
- **Result**: User can now log in and access dashboard

#### 2. Request Resubmission
- **Button**: Orange "Request Resubmission" button
- **Status Change**: `pending` → `request_submission`
- **Additional Updates**:
  - Sets `documentsSubmitted: false`
  - Sets `requestSubmissionAt: [timestamp]`
  - Sets `emailNotificationSent: true`
  - Optional: `rejectionReason` (if provided by admin)
- **Email Sent**: Resubmission request email to owner
- **Result**: User must resubmit documents

#### 3. Reject
- **Button**: Red "Reject" button
- **Status Change**: `pending` → `rejected`
- **Additional Updates**:
  - Sets `documentsSubmitted: false`
  - Sets `rejectedAt: [timestamp]`
  - Sets `emailNotificationSent: true`
  - Optional: `rejectionReason` (if provided by admin)
- **Email Sent**: Rejection notification email to owner
- **Result**: User must sign up again

---

## Method 2: Cloud Function via Email Links

### Location
- **File**: `functions/index.js`
- **Function**: `handleApproval`
- **Endpoint**: `https://[your-project].cloudfunctions.net/handleApproval`

### How It Works
1. When owner submits documents, admin receives email with:
   - User details
   - Attached documents
   - **Two clickable links:**
     - ✅ Approve link
     - 📋 Request Resubmission link

2. Admin clicks link in email
3. Link opens Cloud Function endpoint with:
   - `token`: One-time approval token
   - `action`: "approve" or "resubmission"
   - `reason`: (optional) Reason for resubmission

4. Cloud Function:
   - Validates token (checks expiry, usage)
   - Sends confirmation email to owner
   - Updates Firestore with new status
   - Marks token as used

### Example URL Format
```
https://us-central1-your-project.cloudfunctions.net/handleApproval?token=ABC123&action=approve
https://us-central1-your-project.cloudfunctions.net/handleApproval?token=ABC123&action=resubmission&reason=Blurry%20images
```

### Status Changes
- **Action: "approve"** → `pending` → `approved`
- **Action: "resubmission"** → `pending` → `request_submission`

---

## Method 3: Email Reply Processing (Future/Alternative)

### Location
- **File**: `lib/services/email_processor_service.dart`
- **Function**: `_handleAdminReply`

### How It Works
1. Admin receives email about pending registration
2. Admin replies to email with:
   - **Subject line**: 
     - `APPROVE [userId]` → Approves user
     - `REJECT [userId]` → Rejects user
   - **Body** (optional): Reason for rejection

3. Email processor service:
   - Monitors incoming emails
   - Parses subject line for decision and userId
   - Extracts reason from body (if present)
   - Updates Firestore status
   - Sends notification email to owner

### Status Changes
- **Subject: "APPROVE [userId]"** → `pending` → `approved`
- **Subject: "REJECT [userId]"** → `pending` → `rejected`

---

## Status Flow Summary

```
┌─────────┐
│ pending │ (Initial state after document submission)
└────┬────┘
     │
     ├───[Approve]───────────► approved ──► User can login ✅
     │
     ├───[Request Resubmission]─► request_submission ──► User must resubmit 📋
     │
     └───[Reject]─────────────► rejected ──► User must sign up again ❌
```

---

## After Approval - Google Login

### For Users with `authProvider: "google"`

Once a user's status changes to `approved`, they can log in using Google:

1. **Login Process**:
   - User clicks "Continue with Google" on owner login screen
   - System checks approval status in Firestore
   - If `approvalStatus == "approved"`:
     - ✅ User successfully logs in
     - Shows "You Successfully Logged In!" message
     - Redirects to `/owner-dashboard`

2. **Code Flow**:
   - **File**: `lib/screens/owner_login_screen.dart`
   - **Function**: `_signInWithGoogle()`
   - Checks status after Google authentication
   - Routes based on approval status:
     - `approved` → Dashboard ✅
     - `pending` → Waiting approval screen
     - `request_submission` → Document upload screen
     - `rejected` → Sign up screen (with rejection message)

3. **Verification**:
   - System verifies user is owner role
   - System checks `approvalStatus` in Firestore
   - System ensures `emailNotificationSent: true` (allows login)

---

## Important Fields Updated on Approval

When status changes from `pending` to `approved`:

```javascript
{
  approvalStatus: "approved",
  emailNotificationSent: true,
  approvedAt: [serverTimestamp],
  documentsSubmitted: true,
  // For Cloud Function method:
  approvalProcessedVia: "emailLink",
  approvalProcessedAt: [serverTimestamp],
  approvalAction: "approve"
}
```

---

## Admin Access Requirements

To use the Admin Approval Screen:
- User must have `role: "admin"` in their Firestore document
- Admin routes should be protected in your app
- Ensure only admin users can access `/admin-approval` route

