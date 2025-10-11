import 'package:flutter/material.dart';
import 'package:location/location.dart';

class SpeedIndicator extends StatelessWidget {
  final double? speed; // Speed in m/s

  const SpeedIndicator({
    super.key,
    this.speed,
  });

  @override
  Widget build(BuildContext context) {
    if (speed == null) return const SizedBox.shrink();

    // Convert m/s to km/h
    final speedKmh = (speed! * 3.6).round();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.speed,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            '$speedKmh km/h',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
} 