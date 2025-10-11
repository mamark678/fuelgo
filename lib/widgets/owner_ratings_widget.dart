import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/user_service_fixed.dart'; // Import the fixed user service

class OwnerRatingsWidget extends StatelessWidget {
  final String ownerId;

  const OwnerRatingsWidget({
    Key? key,
    required this.ownerId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('station_ratings')
          .where('ownerId', isEqualTo: ownerId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading ratings: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final ratings = snapshot.data?.docs ?? [];

        if (ratings.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No Ratings Yet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Ratings will appear here when customers rate your stations',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: ratings.length,
          itemBuilder: (context, index) {
            final ratingData = ratings[index].data() as Map<String, dynamic>;
            return OwnerRatingCard(
              ratingData: ratingData,
              ratingId: ratings[index].id,
            );
          },
        );
      },
    );
  }
}

class OwnerRatingCard extends StatelessWidget {
  final Map<String, dynamic> ratingData;
  final String ratingId;

  const OwnerRatingCard({
    Key? key,
    required this.ratingData,
    required this.ratingId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final rating = (ratingData['rating'] ?? 0.0).toDouble();
    final userId = ratingData['userId'] ?? '';
    final stationName = ratingData['stationName'] ?? 'Unknown Station';
    final createdAt = ratingData['createdAt'] as Timestamp?;
    final formattedDate = createdAt != null 
        ? DateFormat('MMM dd, yyyy - hh:mm a').format(createdAt.toDate())
        : 'Recently';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                      Text(
                        stationName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                FutureBuilder<String>(
                  future: UserServiceFixed.getUserName(userId),
                  builder: (context, snapshot) {
                    final userName = snapshot.data ?? 'User';
                    return Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    );
                  },
                ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
