import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;
  String? _message;
  String? _error;

  void _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _message = null;
      _error = null;
    });
    try {
      await AuthService().sendPasswordResetEmail(_emailController.text.trim());
      setState(() {
        _message = 'Password reset email sent!';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) => value == null || value.isEmpty ? 'Enter your email' : null,
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              if (_message != null) ...[
                Text(_message!, style: const TextStyle(color: Colors.green)),
                const SizedBox(height: 8),
              ],
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _sendResetEmail,
                      child: const Text('Send Reset Email'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
} 