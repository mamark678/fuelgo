import 'package:flutter/material.dart';

import '../services/navigation_service.dart';

class NavigationOverlay extends StatelessWidget {
  final NavigationService navigationService;
  final VoidCallback? onStopNavigation;

  const NavigationOverlay({
    super.key,
    required this.navigationService,
    this.onStopNavigation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with navigation icon and stop button
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.navigation,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                fit: FlexFit.loose,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Navigation Active',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Following route to destination',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onStopNavigation,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Navigation info cards
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: _buildInfoCard(
                  'Distance',
                  navigationService.distance,
                  Icons.straighten,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.loose,
                child: _buildInfoCard(
                  'Duration',
                  navigationService.duration,
                  Icons.access_time,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.loose,
                child: _buildInfoCard(
                  'ETA',
                  navigationService.eta,
                  Icons.schedule,
                  Colors.blue,
                ),
              ),
            ],
          ),
          
          // Next turn instruction
          if (navigationService.nextTurn.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.turn_right,
                    color: Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Text(
                      navigationService.nextTurn,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Route steps (collapsible)
          if (navigationService.routeSteps.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildRouteSteps(),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSteps() {
    return ExpansionTile(
      title: const Text(
        'Turn-by-turn Directions',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      leading: const Icon(Icons.list, color: Colors.blue),
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: navigationService.routeSteps.length,
          itemBuilder: (context, index) {
            final step = navigationService.routeSteps[index];
            final isCurrentStep = index == navigationService.currentStepIndex;
            
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isCurrentStep ? Colors.blue[50] : Colors.grey[50],
                borderRadius: BorderRadius.circular(6),
                border: isCurrentStep 
                    ? Border.all(color: Colors.blue[200]!)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isCurrentStep ? Colors.blue : Colors.grey[400],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.instruction,
                          style: TextStyle(
                            fontWeight: isCurrentStep ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${step.distance} • ${step.duration}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
} 