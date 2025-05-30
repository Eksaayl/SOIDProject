import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';
import '../landing.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passCtrl     = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passCtrl.text != _confirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      final uid = cred.user!.uid;
      debugPrint('🔑 Auth signup succeeded, uid = $uid');

      try {
        await _firestore.collection('users').doc(uid).set({
          'username': _usernameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'role': 'user',
          'createdAt': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ Firestore write succeeded for user $uid');
      } catch (fireErr, fireSt) {
        debugPrint('❌ Firestore write failed: $fireErr\n$fireSt');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Couldn’t save user data: $fireErr')),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful!')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Landing()),
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


  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    IconData? icon,
    String? Function(String?)? validator,
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
                  _buildTextField(
                    controller: _usernameCtrl,
                    hint: 'Username',
                    icon: Icons.person,
                    validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter your username' : null,
                  ),
                  _buildTextField(
                    controller: _emailCtrl,
                    hint: 'Email',
                    icon: Icons.email,
                    validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter your email' : null,
                  ),
                  _buildTextField(
                    controller: _passCtrl,
                    hint: 'Password',
                    obscure: true,
                    icon: Icons.lock,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter your password';
                      if (v.length < 6) return 'Minimum 6 characters';
                      return null;
                    },
                  ),
                  _buildTextField(
                    controller: _confirmCtrl,
                    hint: 'Confirm Password',
                    obscure: true,
                    icon: Icons.lock_outline,
                    validator: (v) =>
                    (v == null || v.isEmpty) ? 'Confirm your password' : null,
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
