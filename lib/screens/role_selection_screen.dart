import 'package:flutter/material.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Your Role')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/fuelgo1.png', height: 120, fit: BoxFit.contain),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.directions_car),
                label: const Text('I am a Driver'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.local_gas_station),
                label: const Text('I am the Gas Station Owner'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: Colors.orange,
                  textStyle: const TextStyle(fontSize: 18),
                ),
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/owner-login');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
} 