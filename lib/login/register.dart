import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';
import '../startup.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';

class RegisterPage extends StatefulWidget {
  final bool isGoogleSignIn;
  final String initialUsername;
  final String initialPhotoUrl;
  final String initialEmail;
  const RegisterPage({super.key, this.isGoogleSignIn = false, this.initialUsername = '', this.initialPhotoUrl = '', this.initialEmail = ''});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _emailCtrl;
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  final _serviceCtrl  = TextEditingController();
  final _mobileCtrl   = TextEditingController();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _showUsernameHelp = false;
  bool _acceptedTerms = false;
  bool _viewedTerms = false;
  bool _viewedPrivacy = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  Uint8List? _pickedImage;
  
  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;
  bool _showPasswordRequirements = false;
  bool _showMobileHelp = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.initialUsername);
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _usernameCtrl.addListener(() {
      setState(() {
        _showUsernameHelp = _usernameCtrl.text.isNotEmpty;
      });
    });
    _mobileCtrl.addListener(() {
      setState(() {
        _showMobileHelp = _mobileCtrl.text.isNotEmpty;
      });
    });
    _passCtrl.addListener(_validatePassword);
    if (widget.initialPhotoUrl.isNotEmpty) {
      _fetchInitialPhoto(widget.initialPhotoUrl);
    }
  }

  Future<void> _fetchInitialPhoto(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await NetworkAssetBundle(uri).load(url);
      setState(() {
        _pickedImage = response.buffer.asUint8List();
      });
    } catch (e) {
      // Ignore errors, user can still upload a new photo
    }
  }

  void _validatePassword() {
    final password = _passCtrl.text;
    setState(() {
      _showPasswordRequirements = password.isNotEmpty;
      _hasMinLength = password.length >= 8;
      _hasUppercase = password.contains(RegExp(r'[A-Z]'));
      _hasLowercase = password.contains(RegExp(r'[a-z]'));
      _hasNumber = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    });
  }

  bool _isPasswordValid() {
    return _hasMinLength && _hasUppercase && _hasLowercase && _hasNumber && _hasSpecialChar;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _serviceCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      final fileName = picked.name.toLowerCase();
      if (!fileName.endsWith('.jpg') && !fileName.endsWith('.jpeg') && !fileName.endsWith('.png')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select only JPEG (.jpg/.jpeg) or PNG (.png) files.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final bytes = await picked.readAsBytes();
      setState(() {
        _pickedImage = bytes;
      });
    }
  }

  Future<String?> _uploadProfilePhoto() async {
    if (_pickedImage == null) return null;
    
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;
      
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child('$uid.jpg');
      
      final uploadTask = storageRef.putData(_pickedImage!);
      final snapshot = await uploadTask;
      
      final downloadURL = await snapshot.ref.getDownloadURL();
      debugPrint('✅ Profile photo uploaded: $downloadURL');
      
      return downloadURL;
    } catch (e) {
      debugPrint('❌ Failed to upload profile photo: $e');
      return null;
    }
  }

  void _showTermsAndConditions() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.grey[50]!,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xff021e84),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.description,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Terms and Conditions',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _viewedTerms = true;
                        });
                      },
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xff021e84).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xff021e84).withOpacity(0.2),
                          ),
                        ),
                        child: const Text(
                          'By using this application, you agree to the following terms:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff021e84),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      _buildTermItem('1', 'You will provide accurate and truthful information during registration.'),
                      _buildTermItem('2', 'You are responsible for maintaining the confidentiality of your account.'),
                      _buildTermItem('3', 'You will not use this application for any unlawful purposes.'),
                      _buildTermItem('4', 'The application administrators reserve the right to modify these terms at any time.'),
                      _buildTermItem('5', 'Your account may be suspended or terminated for violations of these terms.'),
                      
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Last updated: ${DateTime.now().year}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      setState(() {
        _viewedTerms = true;
      });
    });
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      barrierDismissible: true, 
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Colors.grey[50]!,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xff021e84),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.privacy_tip,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _viewedPrivacy = true;
                        });
                      },
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xff021e84).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xff021e84).withOpacity(0.2),
                          ),
                        ),
                        child: const Text(
                          'Your privacy is important to us. This policy explains how we collect and use your information:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff021e84),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      _buildPrivacyItem('We collect your email, username, and profile photo for account creation.'),
                      _buildPrivacyItem('Your data is stored securely using Firebase authentication and Firestore.'),
                      _buildPrivacyItem('We do not share your personal information with third parties.'),
                      _buildPrivacyItem('You can request deletion of your account and data at any time.'),
                      _buildPrivacyItem('We use cookies and similar technologies to improve your experience.'),
                      
                      const SizedBox(height: 20),
                      
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xff021e84).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xff021e84).withOpacity(0.2),
                          ),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Data Privacy Act (Republic Act No. 10173) Compliance',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xff021e84),
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'In compliance with the Data Privacy Act of 2012, we ensure:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      _buildPrivacyItem('Transparency: Clear information about data collection and processing.'),
                      _buildPrivacyItem('Legitimate Purpose: Data is collected only for specified, legitimate purposes.'),
                      _buildPrivacyItem('Proportionality: We collect only necessary and relevant information.'),
                      _buildPrivacyItem('Data Quality: We maintain accurate and up-to-date personal information.'),
                      _buildPrivacyItem('Security: Appropriate security measures protect your personal data.'),
                      _buildPrivacyItem('Retention: Data is retained only for as long as necessary.'),
                      _buildPrivacyItem('Access: You have the right to access and correct your personal data.'),
                      _buildPrivacyItem('Breach Notification: We will notify you of any data breaches affecting your information.'),
                      
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Last updated: ${DateTime.now().year}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      setState(() {
        _viewedPrivacy = true;
      });
    });
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    
    // For Google Sign-In users, they already have a photo from Google
    // For regular users, require a photo to be taken
    if (!widget.isGoogleSignIn && _pickedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a photo or select an image first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the terms and conditions'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (!widget.isGoogleSignIn) {
      if (!_isPasswordValid()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password does not meet security requirements. Please check the password criteria.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (_passCtrl.text != _confirmCtrl.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Passwords do not match'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final usernameToCheck = _usernameCtrl.text.trim();
    final emailToCheck = _emailCtrl.text.trim();
    
    final existingUsers = await _firestore.collection('users').get();
    final existingUsernames = existingUsers.docs
        .map((doc) => doc.data()['username'] as String?)
        .where((username) => username != null)
        .map((username) => username!.toLowerCase())
        .toSet();
    
    if (existingUsernames.contains(usernameToCheck.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Username already exists (case-insensitive). Please choose another.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (!widget.isGoogleSignIn) {
      final existingEmails = existingUsers.docs
          .map((doc) => doc.data()['email'] as String?)
          .where((email) => email != null)
          .map((email) => email!.toLowerCase())
          .toSet();
      if (existingEmails.contains(emailToCheck.toLowerCase())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email already exists (case-insensitive). Please use a different email.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      String? photoURL;
      
      if (widget.isGoogleSignIn) {
        // For Google Sign-In users, use the existing Google photo URL
        final user = _auth.currentUser;
        if (user == null) throw Exception('No authenticated user');
        
        // Use Google's photo URL if available, otherwise use uploaded photo
        photoURL = user.photoURL;
        if (_pickedImage != null) {
          // If user uploaded a new photo, use that instead
          photoURL = await _uploadProfilePhoto();
        }
        
        await _firestore.collection('users').doc(user.uid).set({
          'username': _usernameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'service': _serviceCtrl.text.trim(),
          'mobile': _mobileCtrl.text.trim(),
          'photoURL': photoURL,
          'role': 'user',
          'profileComplete': true,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('✅ Firestore write succeeded for Google user ${user.uid}');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StartupPage()),
        );
        return;
      }

      final cred = await _auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      final uid = cred.user!.uid;
      debugPrint('🔑 Auth signup succeeded, uid = $uid');

      // For regular registration, upload photo after user is created
      if (_pickedImage != null) {
        photoURL = await _uploadProfilePhoto();
      }

      try {
        await _firestore.collection('users').doc(uid).set({
          'username': _usernameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'service': _serviceCtrl.text.trim(),
          'mobile': _mobileCtrl.text.trim(),
          'photoURL': photoURL, 
          'role': 'user',
          'createdAt': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ Firestore write succeeded for user $uid');
      } catch (fireErr, fireSt) {
        debugPrint('❌ Firestore write failed: $fireErr\n$fireSt');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Couldn\'t save user data: $fireErr')),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful!')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const StartupPage()),
      );

    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Auth signup failed: ${e.code} ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: ${e.message}')),
      );
    } catch (e, st) {
      debugPrint('❌ Unexpected error in _register: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unexpected error — please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTermItem(String index, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$index. ',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xff021e84),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle,
            color: Color(0xff021e84),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    IconData? icon,
    String? Function(String?)? validator,
    bool readOnly = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          icon: icon != null ? Icon(icon, color: Colors.grey) : null,
          hintText: hint,
          border: InputBorder.none,
        ),
        validator: validator,
        readOnly: readOnly,
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: _passCtrl,
        obscureText: !_showPassword,
        decoration: InputDecoration(
          icon: const Icon(Icons.lock, color: Colors.grey),
          hintText: 'Password',
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: Icon(
              _showPassword ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _showPassword = !_showPassword;
              });
            },
          ),
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Enter your password';
          if (!_isPasswordValid()) return 'Password does not meet requirements';
          return null;
        },
      ),
    );
  }

  Widget _buildConfirmPasswordField() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: _confirmCtrl,
        obscureText: !_showConfirmPassword,
        decoration: InputDecoration(
          icon: const Icon(Icons.lock_outline, color: Colors.grey),
          hintText: 'Confirm Password',
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: Icon(
              _showConfirmPassword ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _showConfirmPassword = !_showConfirmPassword;
              });
            },
          ),
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Confirm your password';
          if (v != _passCtrl.text) return 'Passwords do not match';
          return null;
        },
      ),
    );
  }

  Widget _buildPasswordValidationWidget() {
    return Container(
      margin: const EdgeInsets.only(top: 8, left: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password Requirements:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          _buildValidationItem('At least 8 characters', _hasMinLength),
          _buildValidationItem('At least one uppercase letter (A-Z)', _hasUppercase),
          _buildValidationItem('At least one lowercase letter (a-z)', _hasLowercase),
          _buildValidationItem('At least one number (0-9)', _hasNumber),
          _buildValidationItem('At least one special character (!@#\$%^&*)', _hasSpecialChar),
        ],
      ),
    );
  }

  Widget _buildValidationItem(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: isValid ? Colors.green : Colors.white70,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: isValid ? Colors.green : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff021e84),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 300,
            maxWidth: 600,
            minHeight: 500,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_pickedImage != null)
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: MemoryImage(_pickedImage!),
                    )
                  else if (widget.isGoogleSignIn && widget.initialPhotoUrl.isNotEmpty)
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: NetworkImage(widget.initialPhotoUrl),
                    )
                  else
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.grey[300],
                      child: Icon(Icons.person, size: 48, color: Colors.white),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickImage,
                        icon: Icon(Icons.camera_alt),
                        label: Text('Take Photo or Select Image'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Color(0xff021e84),
                        ),
                      ),
                      if (!widget.isGoogleSignIn) ...[
                        const SizedBox(width: 8),
                        Text(
                          '*',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isGoogleSignIn 
                        ? 'Photo is optional (using Google profile picture)'
                        : 'Photo is required',
                    style: TextStyle(
                      color: widget.isGoogleSignIn ? Colors.white70 : Colors.red[300],
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sign up',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create your account',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 32),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTextField(
                        controller: _usernameCtrl,
                        hint: 'Username',
                        icon: Icons.person,
                        validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter your username' : null,
                      ),
                      if (_showUsernameHelp)
                        Container(
                          margin: EdgeInsets.only(top: 4, left: 8),
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Please follow a standardized format: "Juan Dela Cruz" → "j.delacruz" or "John Philip Cruz" → "jp.cruz"',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      _buildTextField(
                        controller: _emailCtrl,
                        hint: 'Email',
                        icon: Icons.email,
                        validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter your email' : null,
                        readOnly: widget.isGoogleSignIn,
                      ),
                      _buildTextField(
                        controller: _serviceCtrl,
                        hint: 'Service/Division',
                        icon: Icons.business,
                        validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter your service/division' : null,
                      ),
                      _buildTextField(
                        controller: _mobileCtrl,
                        hint: 'Mobile Number',
                        icon: Icons.phone,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Enter your mobile number';
                          final phoneRegex = RegExp(r'^(\+63|0)?9\d{9}$');
                          if (!phoneRegex.hasMatch(v.replaceAll(RegExp(r'[\s\-\(\)]'), ''))) {
                            return 'Please enter a valid Philippine mobile number';
                          }
                          return null;
                        },
                      ),
                      if (_showMobileHelp)
                        Container(
                          margin: EdgeInsets.only(top: 4, left: 8),
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Preferably Viber for better communication',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      if (!widget.isGoogleSignIn) ...[
                        _buildPasswordField(),
                        _buildConfirmPasswordField(),
                        if (_showPasswordRequirements) _buildPasswordValidationWidget(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Checkbox(
                        value: _acceptedTerms,
                        onChanged: (_viewedTerms && _viewedPrivacy) ? (value) {
                          setState(() {
                            _acceptedTerms = value ?? false;
                          });
                        } : null,
                        activeColor: const Color(0xff021e84),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: (_viewedTerms && _viewedPrivacy) ? () {
                            setState(() {
                              _acceptedTerms = !_acceptedTerms;
                            });
                          } : null,
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: (_viewedTerms && _viewedPrivacy) ? Colors.white : Colors.white60,
                                fontSize: 14,
                              ),
                              children: [
                                TextSpan(text: 'I agree to the '),
                                TextSpan(
                                  text: 'Terms and Conditions',
                                  style: TextStyle(
                                    decoration: TextDecoration.underline,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = _showTermsAndConditions,
                                ),
                                TextSpan(text: ' and '),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: TextStyle(
                                    decoration: TextDecoration.underline,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = _showPrivacyPolicy,
                                ),
                                TextSpan(text: ' (including Data Privacy Act consent)'),
                                if (!(_viewedTerms && _viewedPrivacy))
                                  TextSpan(
                                    text: '\n(Please read both documents first)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange[300],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: _isLoading ? null : _register,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Color(0xff021e84))
                          : const Text(
                        'Sign up',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Already have an account?',
                        style: TextStyle(color: Colors.white70),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginPage()),
                          );
                        },
                        child: const Text(
                          'Login',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
