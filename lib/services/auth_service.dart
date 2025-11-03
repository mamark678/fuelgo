// lib/services/auth_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();



  Future<User?> signUp({
  required String email,
  required String password,
  required String name,
  Map<String, dynamic>? extraData,
}) async {
  try {
    print('Starting signUp for email: $email');
    
    UserCredential result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = result.user;
    if (user != null) {
      print('User created successfully: ${user.uid}');
      
      // Send verification email (non-blocking - don't fail signup if email sending fails)
      if (!user.emailVerified) {
        try {
          await user.sendEmailVerification();
          print("Verification email sent to $email");
        } catch (e) {
          // Log error but don't throw - account creation succeeded, user can request verification email later
          print("Warning: Error sending verification email (account still created): $e");
          // Don't re-throw - allow signup to complete successfully
        }
      }

      // Store Firestore profile
      final userData = {
        'email': email,
        'name': name,
        'role': 'user', // default
        'createdAt': FieldValue.serverTimestamp(),
        'authProvider': 'email', // Track auth method
        'emailVerified': false,   // start as false
        ...?extraData,
      };

      await _db.collection('users').doc(user.uid).set(userData);
      print('Firestore document created for user: ${user.uid}');

      // Update displayName for AuthWrapper
      String userRole = extraData?['role'] ?? 'customer';
      await user.updateDisplayName(userRole);

      return user;
    }

    return null;
  } catch (e) {
    print('SignUp error: $e');
    rethrow;
  }
}


  // Login (existing) - for customers only
  Future<User?> login({
    required String email,
    required String password,
  }) async {
    UserCredential result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Check user role and prevent owners from logging in as customers
    if (result.user != null) {
      String? userRole = await getUserRole(result.user!.uid);
      if (userRole != null) {
        if (userRole == 'owner') {
          await signOut();
          throw Exception('Access denied. This account is registered as a gas station owner. Please use the Owner Login instead.');
        }
        await result.user!.updateDisplayName(userRole);
      }
    }

    return result.user;
  }

Future<Map<String, dynamic>?> signInWithGoogleAsCustomer() async {
  try {
    // 1. Trigger Google Sign-In
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // user canceled login

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

    // 2. Create Google credential
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // 3. Sign in with Firebase
    final UserCredential userCredential =
        await _auth.signInWithCredential(credential);
    final User? user = userCredential.user;

    if (user == null) return null;

    // 4. Check if first-time Google login
    final bool isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

    if (isNewUser) {
      // 5. Create Firestore user profile
      final userData = {
        'uid': user.uid,
        'email': user.email,
        'name': user.displayName ?? 'User',
        'photoURL': user.photoURL,
        'role': 'customer',
        'authProvider': 'google',
        'emailVerified': user.emailVerified,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _db.collection('users').doc(user.uid).set(userData);
    } else {
      // 6. Check if existing user is an owner - prevent owners from customer login
      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final role = userData['role'] as String? ?? 'customer';
        
        if (role == 'owner') {
          await signOut();
          await GoogleSignIn().signOut();
          throw Exception('Access denied. This Google account is registered as a gas station owner. Please use the Owner Login instead.');
        }
      }
    }

    // 7. Return result
    return {
      'user': user,
      'isNewUser': isNewUser,
    };
  } catch (e) {
    print("Google Sign-In error: $e");
    rethrow; // Re-throw so caller can handle the error
  }
}

Future<Map<String, dynamic>?> signInWithGoogleAsOwner() async {
  try {
    if (kIsWeb) {
      // Web flow (keep existing logic)
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});
      final UserCredential result = await _auth.signInWithPopup(provider);
      final User? firebaseUser = result.user;
      final OAuthCredential? oauthCred = result.credential as OAuthCredential?;
      if (firebaseUser == null) return null;

      final email = firebaseUser.email ?? '';
      final displayName = firebaseUser.displayName ?? 'Owner';
      final photoURL = firebaseUser.photoURL;

      // For web, we can check after signing in since popup already authenticated
      final userDoc = await _db.collection('users').doc(firebaseUser.uid).get();
      
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final role = userData['role'] as String? ?? '';
        final approvalStatus = userData['approvalStatus'] as String?;

        if (role == 'owner') {
          // Check if this is a rejected owner trying to re-register
          if (approvalStatus == 'rejected') {
            // For rejected owners trying to sign up again:
            // Delete their Firestore document and treat them as a new user
            // so they can go through verification/document upload again
            await _db.collection('users').doc(firebaseUser.uid).delete();
            try {
              await firebaseUser.delete();
            } catch (e) {
              print('Warning: failed to delete temporary web user (owner): $e');
            }
            await _auth.signOut();

            final userDataForSignup = {
              'name': displayName,
              'email': email,
              'photoURL': photoURL,
            };

            return {
              'user': null,
              'isNewUser': true, // Treat as new user - go to verification
              'userData': userDataForSignup,
              'credential': oauthCred,
            };
          } else if (approvalStatus == 'approved' || approvalStatus == 'request_submission') {
            await firebaseUser.updateDisplayName('owner');
            return {
              'user': firebaseUser,
              'isNewUser': false,
            };
          } else if (approvalStatus == 'pending') {
            await _auth.signOut();
            throw Exception('Your owner account is pending admin approval. Please wait for approval before signing in.');
          } else {
            await _auth.signOut();
            throw Exception('Your owner account has not been approved. Please contact admin.');
          }
        } else {
          await firebaseUser.updateDisplayName('customer');
          await _auth.signOut();
          throw Exception('Access denied. This Google account is not registered as a gas station owner.');
        }
      } else {
        // New owner
        try {
          await firebaseUser.delete();
        } catch (e) {
          print('Warning: failed to delete temporary web user (owner): $e');
        }
        await _auth.signOut();

        final userData = {
          'name': displayName,
          'email': email,
          'photoURL': photoURL,
        };

        return {
          'user': null,
          'isNewUser': true,
          'userData': userData,
          'credential': oauthCred,
        };
      }
    }

    // MOBILE owner flow - Try sign-in first approach
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}

    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;
    
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final email = googleUser.email;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // Strategy: Try to sign in first, then check Firestore
    // If sign-in fails, we know it's a new user
    try {
      final UserCredential result = await _auth.signInWithCredential(credential);
      final User? user = result.user;
      
      if (user != null) {
        // Successfully signed in - now check if they're an owner in Firestore
        try {
          final userDoc = await _db.collection('users').doc(user.uid).get();
          
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            final role = userData['role'] as String? ?? '';
            final approvalStatus = userData['approvalStatus'] as String?;
            final emailNotificationSent = userData['emailNotificationSent'] as bool? ?? false;
            final documentsSubmitted = userData['documentsSubmitted'] as bool? ?? false;

              if (role == 'owner') {
              // Check if this is a rejected owner trying to re-register
              if (approvalStatus == 'rejected') {
                // For rejected owners trying to sign up again:
                // Delete their Firestore document and treat them as a new user
                // so they can go through verification/document upload again
                await _db.collection('users').doc(user.uid).delete();
                await _auth.signOut();
                await _googleSignIn.signOut();

                final userData = {
                  'name': googleUser.displayName ?? 'Owner',
                  'email': googleUser.email,
                  'photoURL': googleUser.photoUrl,
                };

                return {
                  'user': null,
                  'isNewUser': true, // Treat as new user - go to verification
                  'userData': userData,
                  'credential': credential,
                };
              } else {
                // Allow login for all other statuses - login screen will handle routing
                await user.updateDisplayName('owner');
                return {
                  'user': user,
                  'isNewUser': false,
                  'userData': userData, // Pass userData so login screen can check verification status
                };
              }
            } else {
              // User exists but not an owner
              await _auth.signOut();
              await _googleSignIn.signOut();
              throw Exception('Access denied. This Google account is not registered as a gas station owner.');
            }
          } else {
            // User exists in Firebase Auth but no Firestore document
            // This means they're a NEW USER who should go to verification
            await _auth.signOut();
            await _googleSignIn.signOut();

            final userData = {
              'name': googleUser.displayName ?? 'Owner',
              'email': googleUser.email,
              'photoURL': googleUser.photoUrl,
            };

            return {
              'user': null,
              'isNewUser': true, // New user - go to verification
              'userData': userData,
              'credential': credential,
            };
          }
        } catch (e) {
          // If Firestore access fails, sign out and rethrow
          await _auth.signOut();
          await _googleSignIn.signOut();
          rethrow;
        }
      }
    } on FirebaseAuthException catch (authError) {
      // Sign-in failed - check if it's because user doesn't exist
      if (authError.code == 'user-not-found' || 
          authError.code == 'account-exists-with-different-credential') {
        // This is a new user - return data for verification flow
        await _auth.signOut();
        await _googleSignIn.signOut();

        final userData = {
          'name': googleUser.displayName ?? 'Owner',
          'email': googleUser.email,
          'photoURL': googleUser.photoUrl,
        };

        return {
          'user': null,
          'isNewUser': true, // New user - go to verification
          'userData': userData,
          'credential': credential,
        };
      } else {
        // Other auth errors - rethrow
        await _auth.signOut();
        await _googleSignIn.signOut();
        rethrow;
      }
    }

    // Fallback - treat as new user if we get here
    await _auth.signOut();
    await _googleSignIn.signOut();

    final userData = {
      'name': googleUser.displayName ?? 'Owner',
      'email': googleUser.email,
      'photoURL': googleUser.photoUrl,
    };

    return {
      'user': null,
      'isNewUser': true,
      'userData': userData,
      'credential': credential,
    };

  } catch (e) {
    print('Google Sign-In Error (owner): $e');
    rethrow;
  }
}

Future<User?> completeGoogleOwnerAfterVerification({
  required String name,
  required String email,
  String? photoURL,
  AuthCredential? credential,
}) async {
  try {
    if (credential == null) {
      throw Exception('Google credential is required');
    }

    // Sign in / create user with google credential
    UserCredential result = await _auth.signInWithCredential(credential);
    User? user = result.user;

    if (user == null) {
      throw Exception('Failed to create Firebase Auth account');
    }

    final userData = {
      'email': email,
      'name': name,
      'photoURL': photoURL,
      'role': 'owner',
      'authProvider': 'google',
      'emailVerified': true,
      'approvalStatus': 'pending', // Pending admin approval
      'pendingDocuments': true,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _db.collection('users').doc(user.uid).set(userData);
    await user.updateDisplayName('owner');

    return user;
  } catch (e) {
    print('Complete Google owner signup after verification error: $e');
    rethrow;
  }
}


  Future<User?> loginOwner({
  required String email,
  required String password,
}) async {
  UserCredential result = await _auth.signInWithEmailAndPassword(
    email: email,
    password: password,
  );

  if (result.user != null) {
    String? userRole = await getUserRole(result.user!.uid);
    if (userRole == 'owner') {
      // Don't block login - let the login screen handle routing based on verification status
      // This allows owners to continue their verification process
      final userDoc = await _db.collection('users').doc(result.user!.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final approvalStatus = userData?['approvalStatus'] as String?;

      // Only block rejected users
      if (approvalStatus == 'rejected') {
        await signOut();
        throw Exception('Cannot Access: Your registration has been rejected. Please sign up again with updated documents.');
      }
      
      // Allow login for all other statuses - login screen will handle routing
      await result.user!.updateDisplayName('owner');
      return result.user;
    } else {
      await signOut();
      throw Exception('Access denied. This account is not registered as a gas station owner.');
    }
  }

  return null;
}
Stream<String?> watchApprovalStatus(String uid) {
  return _db.collection('users').doc(uid).snapshots().map((snapshot) {
    if (snapshot.exists) {
      return snapshot.data()?['approvalStatus'] as String?;
    }
    return null;
  });
}
// Optional: small uniform logger to make printed logs consistent
  void _log(String message) {
    final ts = DateTime.now().toIso8601String();
    print('🔐 [$ts] AuthService: $message');
  }

  /// Backwards-compatible alias — in case some code calls signInWithGoogle()
  Future<Map<String, dynamic>?> signInWithGoogle() async {
    _log('Alias signInWithGoogle() called — delegating to signInWithGoogleAsCustomer()');
    return await signInWithGoogleAsCustomer();
  }

  /// Wrapper that calls signInWithGoogleAsCustomer() but rethrows FirebaseAuthException
  /// so callers can show precise error codes/messages.
  Future<Map<String, dynamic>?> signInWithGoogleOrThrow() async {
    _log('signInWithGoogleOrThrow() called');
    try {
      final result = await signInWithGoogleAsCustomer();
      _log('signInWithGoogleAsCustomer() returned: ${result == null ? 'null' : 'map'}');
      return result;
    } on FirebaseAuthException catch (e, st) {
      // rethrow same exception so UI can switch on e.code
      _log('FirebaseAuthException rethrown: code=${e.code} message=${e.message}');
      _log('Stack: $st');
      rethrow;
    } catch (e, st) {
      // Log and rethrow general exception
      _log('General exception in signInWithGoogleOrThrow: $e');
      _log('Stack: $st');
      rethrow;
    }
  }

  Future<User?> loginCustomer({
    required String email,
    required String password,
  }) async {
    UserCredential result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (result.user != null) {
      // Check if user is an owner - prevent owners from customer login
      String? userRole = await getUserRole(result.user!.uid);
      if (userRole == 'owner') {
        await signOut();
        throw Exception('Access denied. This account is registered as a gas station owner. Please use the Owner Login instead.');
      }
      await result.user!.updateDisplayName('customer');
    }

    return result.user;
  }

  // Google complete signup AFTER verification (important: credential required)
  Future<User?> completeGoogleSignupAfterVerification({
    required String name,
    required String email,
    String? photoURL,
    AuthCredential? credential,
  }) async {
    try {
      if (credential == null) {
        throw Exception('Google credential is required');
      }

      // Sign in / create user with google credential
      UserCredential result = await _auth.signInWithCredential(credential);
      User? user = result.user;

      if (user == null) {
        throw Exception('Failed to create Firebase Auth account');
      }

      final userData = {
        'email': email,
        'name': name,
        'photoURL': photoURL,
        'role': 'customer',
        'authProvider': 'google',
        'emailVerified': true,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _db.collection('users').doc(user.uid).set(userData);
      await user.updateDisplayName('customer');

      return user;
    } catch (e) {
      print('Complete Google signup after verification error: $e');
      rethrow;
    }
  }

  // NEW: Owner signup
  Future<User?> signUpOwner({
    required String email,
    required String password,
    required String name,
    Map<String, dynamic>? extraData,
  }) async {
    final ownerData = {
      'role': 'owner',
      'authProvider': 'email',
      ...?extraData,
    };

    return await signUp(
      email: email,
      password: password,
      name: name,
      extraData: ownerData,
    );
  }

  Future<User?> completeGoogleSignupOwner({
    required String password,
    required String name,
    required String email,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = result.user;
      if (user != null) {
      final userData = {
        'email': email,
        'name': name,
        'role': 'owner',
        'authProvider': 'google',
        'emailVerified': true, // Google verifies the email
        'createdAt': FieldValue.serverTimestamp(),
        ...?extraData,
      };

        await _db.collection('users').doc(user.uid).set(userData);
        await user.updateDisplayName('owner');
        return user;
      }

      return null;
    } catch (e) {
      print('Complete Google signup error: $e');
      throw Exception('Failed to complete registration: ${e.toString()}');
    }
  }

  // Forgot Password
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // Fetch user role
  Future<String?> getUserRole(String uid) async {
    DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) {
      return doc['role'] as String?;
    }
    return null;
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Current user
  User? get currentUser => _auth.currentUser;

  // Get user name from Firestore
  Future<String?> getUserName(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return data['name'] as String?;
      }
      return null;
    } catch (e) {
      print('Error getting user name: $e');
      return null;
    }
  }

  bool get isSignedInWithGoogle => _googleSignIn.currentUser != null;

  Future<String?> getAuthProvider(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return data['authProvider'] as String?;
      }
      return null;
    } catch (e) {
      print('Error getting auth provider: $e');
      return null;
    }
  }

  Future<void> linkGoogleCredential(User user) async {
    try {
      final GoogleSignInAccount? googleUser = _googleSignIn.currentUser;
      if (googleUser == null) {
        final silentUser = await _googleSignIn.signInSilently();
        if (silentUser != null) {
          final googleAuth = await silentUser.authentication;
          final credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          await user.linkWithCredential(credential);
        }
      } else {
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.linkWithCredential(credential);
      }
    } catch (e) {
      print('Error linking Google credential: $e');
    }
  }

  // Send email verification for current Firebase email user
  Future<void> sendEmailVerification() async {
    User? user = _auth.currentUser;
    if (user != null) {
      print('Sending email verification to: ${user.email}');
      if (!user.emailVerified) {
        try {
          await user.sendEmailVerification();
          print('Email verification sent successfully');
        } catch (e) {
          print('Error sending email verification: $e');
          rethrow;
        }
      } else {
        print('User email already verified');
      }
    } else {
      print('No current user to send verification email');
    }
  }

  Future<bool> isEmailVerified() async {
    User? user = _auth.currentUser;
    if (user != null) {
      await user.reload();
      return user.emailVerified;
    }
    return false;
  }

  Future<void> markEmailUserAsVerified(String uid) async {
    await _db.collection('users').doc(uid).update({
      'emailVerified': true,
      'verifiedAt': FieldValue.serverTimestamp(),
    });
  }
}
