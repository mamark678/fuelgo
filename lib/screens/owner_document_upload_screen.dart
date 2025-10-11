// lib/screens/owner_document_upload_screen.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

import '../services/firestore_service.dart';
import 'owner_station_map_select_screen.dart';

class OwnerDocumentUploadScreen extends StatefulWidget {
  final String userId;
  final String name;
  final String email;
  final bool isGoogleUser; // Add this
  final AuthCredential? googleCredential; // Add this
  final bool needsPasswordSetup; // Add this

  const OwnerDocumentUploadScreen({
    Key? key,
    required this.userId,
    required this.name,
    required this.email,
    this.isGoogleUser = false, // Add this
    this.googleCredential, // Add this
    this.needsPasswordSetup = false, // Add this
  }) : super(key: key);

  @override
  State<OwnerDocumentUploadScreen> createState() => _OwnerDocumentUploadScreenState();
}

class _OwnerDocumentUploadScreenState extends State<OwnerDocumentUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _gasStationIdImage;
  File? _governmentIdImage;
  File? _businessPermitImage;
  LatLng? _selectedLatLng;
  String? _selectedStationName;
  bool _isSubmitting = false;
  String? _error;

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _passwordSetupCompleted = false;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    // If Google user needs password setup, start at step 0
    // Otherwise, start at step 1 (station selection)
    _currentStep = widget.needsPasswordSetup ? 0 : 1;
    _passwordSetupCompleted = !widget.needsPasswordSetup;
  }

  void _selectStationLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OwnerStationMapSelectScreen(),
      ),
    );
    if (result != null && result is Map) {
      setState(() {
        _selectedStationName = result['stationName'] as String?;
        _selectedLatLng = LatLng(result['lat'], result['lng']);
      });
    }
  }

  Future<void> _setupPassword() async {
  if (_passwordController.text != _confirmPasswordController.text) {
    setState(() => _error = 'Passwords do not match.');
    return;
  }

  if (_passwordController.text.length < 6) {
    setState(() => _error = 'Password must be at least 6 characters.');
    return;
  }

  setState(() => _isSubmitting = true);

  try {
    // Create the Firebase Auth account with email/password
    User? user = await AuthService().signUpOwner(
      email: widget.email,
      password: _passwordController.text,
      name: widget.name,
      extraData: {
        'authProvider': 'google',
        'emailVerified': true, // Skip verification for Google users
        'approvalStatus': 'pending',
        'pendingDocuments': true,
      },
    );

    if (user != null && widget.googleCredential != null) {
      // Link Google credential
      try {
        await user.linkWithCredential(widget.googleCredential!);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'linkedProviders': ['password', 'google.com'],
          'googleLinked': true,
        });
      } catch (linkError) {
        print('Warning: Failed to link Google credential: $linkError');
      }

      setState(() {
        _passwordSetupCompleted = true;
        _currentStep = 1; // Move to station selection
        _error = null;
      });
    }
  } catch (e) {
    setState(() => _error = 'Failed to setup password: ${e.toString()}');
  } finally {
    setState(() => _isSubmitting = false);
  }
}

  Future<void> _pickImage(String documentType) async {
    final ImageSource? source = await _showImageSourceDialog();
    if (source == null) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (image != null) {
        final file = File(image.path);
        setState(() {
          switch (documentType) {
            case 'gasStation':
              _gasStationIdImage = file;
              break;
            case 'government':
              _governmentIdImage = file;
              break;
            case 'businessPermit':
              _businessPermitImage = file;
              break;
          }
          _error = null;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to pick image: ${e.toString()}';
      });
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordSetupStep() {
  return Card(
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Set Up Your Backup Password',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a password for backup access to your account. You can sign in with either Google or this password.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Create Password',
              hintText: 'Enter your password',
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _confirmPasswordController,
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              hintText: 'Confirm your password',
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          
          _isSubmitting
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _setupPassword,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Set Password & Continue'),
                ),
        ],
      ),
    ),
  );
}

  Widget _buildDocumentCard(String title, String subtitle, File? image, String documentType) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(documentType),
                  icon: Icon(image == null ? Icons.add_a_photo : Icons.edit),
                  label: Text(image == null ? 'Add' : 'Change'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: image == null ? Colors.blue : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            if (image != null) ...[
              const SizedBox(height: 12),
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    image,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _validateForm() {
    if (_selectedStationName == null || _selectedLatLng == null) {
      setState(() => _error = 'Please select your gas station location.');
      return false;
    }
    if (_gasStationIdImage == null) {
      setState(() => _error = 'Please upload your Gas Station ID.');
      return false;
    }
    if (_governmentIdImage == null) {
      setState(() => _error = 'Please upload your Government ID.');
      return false;
    }
    if (_businessPermitImage == null) {
      setState(() => _error = 'Please upload your Business Permit.');
      return false;
    }
    return true;
  }

  Future<void> _createGasStation() async {
    final stationId = 'FG${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    
    await FirestoreService.createOrUpdateGasStation(
      stationId: stationId,
      name: _selectedStationName!,
      brand: 'Shell', // Default brand
      position: _selectedLatLng!,
      address: 'Valencia City, Bukidnon', // Default address
      prices: {
        'Regular': 55.50,
        'Premium': 60.00,
        'Diesel': 52.00,
      },
      ownerId: widget.userId,
      stationName: _selectedStationName,
    );

    // Update user document with station info
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
      'stationName': _selectedStationName,
      'stationId': stationId,
      'stationLat': _selectedLatLng!.latitude,
      'stationLng': _selectedLatLng!.longitude,
      'documentsSubmitted': true,
      'approvalStatus': 'pending',
      'submittedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _sendEmailToAdmin() async {
  print('Starting email send process...');

  try {
    // ========== CONFIG ==========
    const List<String> adminEmails = [
      'stinemarv@gmail.com',
      'andremarcsambile@gmail.com',
    ];

    const String gmailUsername = 'fuelgosystem@gmail.com';
    // IMPORTANT: do NOT hardcode the password in production. Load from secure storage or CI secrets.
    const String gmailPassword = 'zyrn bklc icxq rflt';

    // Cloud Function endpoint that will handle approval/rejection (deploy later)
    // Replace with your actual function URL (region/project).
    const String approvalEndpoint = 'https://us-central1-your-project.cloudfunctions.net/handleApproval';
    // ============================

    // 1) create one-time token in Firestore
    final tokenDocRef = FirebaseFirestore.instance.collection('approvalTokens').doc();
    final token = tokenDocRef.id;
    await tokenDocRef.set({
      'userId': widget.userId,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))), // expires in 7 days
      'used': false,
    });

    final approveEndpointUrl = '$approvalEndpoint?token=${Uri.encodeComponent(token)}&action=approve';
    final rejectEndpointUrl  = '$approvalEndpoint?token=${Uri.encodeComponent(token)}&action=reject';

    print('Created approval token: $token');
    print('Approve endpoint URL: $approveEndpointUrl');
    print('Reject  endpoint URL: $rejectEndpointUrl');

    // Build the pre-filled mailto contents for the admin to send to the owner
    final processedAt = DateTime.now().toString().split('.')[0];
    final ownerEmail = widget.email;
    final ownerName = widget.name;
    final stationName = _selectedStationName ?? '-';

    // APPROVE mailto
    final approveSubject = 'FuelGo Registration APPROVED - Welcome to FuelGo!';
    final approveBody = StringBuffer()
      ..writeln('Dear $ownerName,')
      ..writeln()
      ..writeln('Congratulations! Your gas station registration has been APPROVED.')
      ..writeln()
      ..writeln('Your Registration Details:')
      ..writeln('- Name: $ownerName')
      ..writeln('- Station: $stationName')
      ..writeln('- Status: APPROVED')
      ..writeln('- Processed: $processedAt')
      ..writeln()
      ..writeln('Next Steps:')
      ..writeln('You can now log into your owner account and start managing your gas station. Upload fuel prices, manage inventory, and serve customers through the FuelGo platform.')
      ..writeln()
      ..writeln('If you have any questions or need assistance, don\'t hesitate to reply to this email.')
      ..writeln()
      ..writeln('Best regards,')
      ..writeln('The FuelGo Team')
      ..writeln('FuelGo System Admin')
      ..writeln()
      ..writeln('---');

    final String approveBodyStr = approveBody.toString().replaceAll('\n', '\r\n');
    final String approveBodyEncoded = Uri.encodeComponent(approveBodyStr);
    final approveMailto = 'mailto:$ownerEmail'
        '?subject=${Uri.encodeComponent(approveSubject)}'
        '&body=$approveBodyEncoded';

    // REQUEST RESUBMISSION mailto
    final rejectSubject = 'FuelGo Registration - Document Review Required';
    final rejectBody = StringBuffer()
      ..writeln('Dear $ownerName,')
      ..writeln()
      ..writeln('Your registration requires document review.')
      ..writeln()
      ..writeln('Details:')
      ..writeln('- Name: $ownerName')
      ..writeln('- Station: $stationName')
      ..writeln('- Status: NEEDS RESUBMISSION')
      ..writeln()
      ..writeln('Please resubmit with clearer documents (check for blurry images, expired IDs, or missing info).')
      ..writeln()
      ..writeln('Reply if you have questions.')
      ..writeln()
      ..writeln('Best regards,')
      ..writeln('The FuelGo Team');

    final String rejectBodyStr = rejectBody.toString().replaceAll('\n', '\r\n');
    final String rejectBodyEncoded = Uri.encodeComponent(rejectBodyStr);
    final rejectMailto = 'mailto:$ownerEmail'
        '?subject=${Uri.encodeComponent(rejectSubject)}'
        '&body=$rejectBodyEncoded';

    // 2) create SMTP server
    final smtpServer = gmail(gmailUsername, gmailPassword);

    // 3) build email message to admins (this HTML contains the two mailto links)
    final message = Message()
      ..from = Address(gmailUsername, 'FuelGo System')
      ..recipients.addAll(adminEmails)
      ..headers = {'Reply-To': '${widget.name} <${widget.email}>'}
      ..subject = 'New Owner Registration - ${widget.name}'
      ..text = '''
A new gas station owner registration requires approval.

Owner Details:
- Name: ${widget.name}
- Email: ${widget.email}
- User ID: ${widget.userId}
- Station Name: $stationName
- Station Location: ${_selectedLatLng?.latitude}, ${_selectedLatLng?.longitude}

Submitted at: ${DateTime.now().toIso8601String()}

Approve: $approveEndpointUrl
Reject:  $rejectEndpointUrl
'''
      ..html = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
        body { font-family: Arial, sans-serif; max-width: 680px; margin: 0 auto; color:#333; }
        .header { background: linear-gradient(135deg,#2196F3,#1976D2); color: #fff; padding: 20px; border-radius: 8px 8px 0 0; text-align:center; }
        .content { padding: 20px; border: 1px solid #e6e6e6; border-top: none; }
        .user-info { background: #f8f9fa; padding: 12px; border-radius: 6px; margin-bottom: 18px; }
        .info-table td { padding: 6px 0; vertical-align: top; }
        .actions { text-align:center; margin: 26px 0; }
        .btn { display:inline-block; padding:14px 28px; margin: 0 8px; text-decoration:none; border-radius:6px; font-weight:600; font-size: 16px; }
        .btn-approve { background: #4CAF50; color:#fff; }
        .btn-reject  { background: #f44336; color:#fff; }
        .btn:hover { opacity: 0.9; transform: translateY(-1px); }
        .footer { font-size:12px; color:#777; text-align:center; padding:12px 0; }
        .note { background:#fff3cd; padding:12px; border-radius:6px; margin-top:18px; font-size:13px; }
    </style>
</head>
<body>
    <div class="header">
        <h2>🏪 New Gas Station Owner Registration</h2>
        <div>Registration Approval Required</div>
    </div>

    <div class="content">
        <div class="user-info">
            <table class="info-table" width="100%">
                <tr><td style="width:140px;font-weight:600;">Name:</td><td>$ownerName</td></tr>
                <tr><td style="font-weight:600;">Email:</td><td>$ownerEmail</td></tr>
                <tr><td style="font-weight:600;">Station:</td><td>$stationName</td></tr>
                <tr><td style="font-weight:600;">Location:</td><td>${_selectedLatLng != null ? '${_selectedLatLng!.latitude.toStringAsFixed(5)}, ${_selectedLatLng!.longitude.toStringAsFixed(5)}' : '-'}</td></tr>
                <tr><td style="font-weight:600;">User ID:</td><td style="font-family:monospace">${widget.userId}</td></tr>
                <tr><td style="font-weight:600;">Submitted:</td><td>$processedAt</td></tr>
            </table>
        </div>

        <p style="color:#666;">
            📄 <strong>Documents attached:</strong> Gas Station ID, Government ID, Business Permit
        </p>

        <div class="actions">
            <!-- Approve button opens admin's email client with an approve message pre-filled -->
            <a href="$approveMailto" class="btn btn-approve">✅ APPROVE</a>

            <!-- Request resubmission button opens admin's email client with a resubmission request pre-filled -->
            <a href="$rejectMailto" class="btn btn-reject">📋 REQUEST RESUBMISSION</a>
        </div>

        <div class="note">
            <strong>Instructions:</strong>
            <br>• Click <strong>APPROVE</strong> to open your email client with an approval message pre-filled
            <br>• Click <strong>REQUEST RESUBMISSION</strong> to open your email client asking the owner to resubmit documents
            <br>• The email will automatically open in your email client with the message pre-filled
            <br>• You can edit the message before sending if needed
        </div>
    </div>

    <div class="footer">
        FuelGo Admin System • Click buttons above to send notifications
    </div>
</body>
</html>
''';

    // 4) Attach files if present
    final attachments = <Attachment>[];
    if (_gasStationIdImage != null) {
      attachments.add(FileAttachment(_gasStationIdImage!)..fileName = 'gas_station_id.jpg');
    }
    if (_governmentIdImage != null) {
      attachments.add(FileAttachment(_governmentIdImage!)..fileName = 'government_id.jpg');
    }
    if (_businessPermitImage != null) {
      attachments.add(FileAttachment(_businessPermitImage!)..fileName = 'business_permit.jpg');
    }
    if (attachments.isNotEmpty) {
      message..attachments = attachments;
    }

    print('✅ Message created. Sending via SMTP...');
    final sendReport = await send(message, smtpServer);
    print('✅ Email sent successfully! Send report: $sendReport');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Admin notification sent to ${adminEmails.length} admins!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } on MailerException catch (e) {
    print('❌ MailerException: ${e.message}');
    for (var p in e.problems) {
      print(' - problem: ${p.code} / ${p.msg}');
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email sending failed: ${e.message}'), backgroundColor: Colors.red),
      );
    }
  } catch (e, st) {
    print('❌ Unexpected error sending email: $e\n$st');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  print('🏁 Email send process completed');
}




  Future<void> _submitDocuments() async {
    if (!_validateForm()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // Create gas station
      await _createGasStation();
      
      // Send email to admin
      await _sendEmailToAdmin();

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 48),
                SizedBox(height: 16),
                Text(
                  'Documents submitted successfully!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Your registration is now pending admin approval. You will be notified once approved.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.pushReplacementNamed(context, '/owner-login');
                },
                child: const Text('Continue to Login'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to submit documents: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Upload Owner Documents'),
      automaticallyImplyLeading: false,
    ),
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Complete Your Owner Registration',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Hello ${widget.name}, please complete the following steps to finish your registration.',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Step 1: Password Setup (only for Google users)
            if (widget.needsPasswordSetup && !_passwordSetupCompleted) ...[
              const Text(
                'Step 1: Set Up Your Password',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildPasswordSetupStep(),
              const SizedBox(height: 32),
            ],

            // Step 2/1: Station Selection and Document Upload
            if (_passwordSetupCompleted || !widget.needsPasswordSetup) ...[
              Text(
                widget.needsPasswordSetup ? 'Step 2: Select Your Gas Station Location' : 'Step 1: Select Your Gas Station Location',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.location_on),
                label: Text(_selectedStationName == null ? 'Select Station Location' : 'Selected: $_selectedStationName'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: _selectedStationName == null ? Colors.blue : Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isSubmitting ? null : _selectStationLocation,
              ),

              // Map preview
              if (_selectedLatLng != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: _selectedLatLng!,
                      initialZoom: 16,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c'],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedLatLng!,
                            width: 40,
                            height: 40,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on, color: Colors.red, size: 36),
                                Text(
                                  _selectedStationName ?? 'Selected',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Document Upload Section
              Text(
                widget.needsPasswordSetup ? 'Step 3: Upload Required Documents' : 'Step 2: Upload Required Documents',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              _buildDocumentCard(
                'Gas Station ID',
                'Upload a clear photo of your gas station identification',
                _gasStationIdImage,
                'gasStation',
              ),
              
              _buildDocumentCard(
                'Government ID',
                'Upload a valid government-issued ID (Driver\'s License, Passport, etc.)',
                _governmentIdImage,
                'government',
              ),
              
              _buildDocumentCard(
                'Business Permit',
                'Upload your valid business permit or license',
                _businessPermitImage,
                'businessPermit',
              ),

              const SizedBox(height: 24),
            ], // This closes the if (_passwordSetupCompleted || !widget.needsPasswordSetup) block

            // Error handling (outside the conditional blocks)
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red.shade600, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Submit button (outside the conditional blocks)
            _isSubmitting
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _submitDocuments,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Submit for Admin Approval'),
                  ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'After submission, your documents will be reviewed by our admin team. You will be notified once approved.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}