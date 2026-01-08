import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/animated_button.dart';
import '../widgets/fade_in_widget.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradientTheme = theme.extension<GradientTheme>()!;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: gradientTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeInWidget(
                    delay: const Duration(milliseconds: 200),
                    child: Hero(
                      tag: 'app_logo',
                      child: Image.asset(
                        'assets/fuelgo1.png',
                        height: 160,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeInWidget(
                    delay: const Duration(milliseconds: 400),
                    child: Column(
                      children: [
                        Text(
                          'Welcome to Fuel-GO!',
                          style: theme.textTheme.displayMedium?.copyWith(
                            color: theme.primaryColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose your role to continue',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  FadeInWidget(
                    delay: const Duration(milliseconds: 600),
                    child: Column(
                      children: [
                        AnimatedButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/login');
                          },
                          icon: Icons.directions_car,
                          child: const Text('I am a Traveler'),
                        ),
                        const SizedBox(height: 20),
                        AnimatedButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(
                                context, '/owner-login');
                          },
                          backgroundColor: Colors.white,
                          foregroundColor: theme.primaryColor,
                          icon: Icons.local_gas_station,
                          child: const Text('I am a Gas Station Owner'),
                        ),
                      ],
                    ),
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
