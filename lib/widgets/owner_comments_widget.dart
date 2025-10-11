import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class OwnerCommentsWidget extends StatelessWidget {
  final String ownerId;

  const OwnerCommentsWidget({
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
          return Center(child: Text('Error loading comments: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final comments = snapshot.data?.docs ?? [];

        if (comments.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.reviews_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No Reviews Yet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Reviews will appear here when customers rate your stations',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: comments.length,
          itemBuilder: (context, index) {
            final commentData = comments[index].data() as Map<String, dynamic>;
            return OwnerCommentCard(
              commentData: commentData,
              ratingId: comments[index].id,
            );
          },
        );
      },
    );
  }
}

class OwnerCommentCard extends StatelessWidget {
  final Map<String, dynamic> commentData;
  final String ratingId;

  const OwnerCommentCard({
    Key? key,
    required this.commentData,
    required this.ratingId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final rating = (commentData['rating'] ?? 0.0).toDouble();
    final comment = commentData['comment'] ?? '';
    final userName = commentData['userName'] ?? 'Anonymous User';
    final stationName = commentData['stationName'] ?? 'Unknown Station';
    final createdAt = commentData['createdAt'] as Timestamp?;
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
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
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
            if (comment.isNotEmpty)
              Text(
                comment,
                style: const TextStyle(fontSize: 14),
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
                TextButton(
                  onPressed: () => _showReplyDialog(context),
                  child: const Text('Reply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showReplyDialog(BuildContext context) {
    final TextEditingController replyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reply to Review'),
          content: TextField(
            controller: replyController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Write your reply...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Save reply to Firestore
                await FirebaseFirestore.instance
                    .collection('station_ratings')
                    .doc(ratingId)
                    .update({
                  'ownerReply': replyController.text.trim(),
                  'ownerReplyAt': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
              },
              child: const Text('Send Reply'),
            ),
          ],
        );
      },
    );
  }
}
