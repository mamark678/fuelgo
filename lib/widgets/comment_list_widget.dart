import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fuelgo/services/user_service_fixed.dart';
import 'package:intl/intl.dart';

import 'animated_card.dart';
import 'fade_in_widget.dart';

class CommentListWidget extends StatefulWidget {
  final String stationId;
  final String currentUserId;
  final VoidCallback? onRefreshRequested;

  const CommentListWidget({
    Key? key,
    required this.stationId,
    required this.currentUserId,
    this.onRefreshRequested,
  }) : super(key: key);

  @override
  CommentListWidgetState createState() => CommentListWidgetState();
}

class CommentListWidgetState extends State<CommentListWidget> {
  List<QueryDocumentSnapshot> _comments = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('station_ratings')
          .where('stationId', isEqualTo: widget.stationId)
          .orderBy('createdAt', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _comments = snapshot.docs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> refreshComments() async {
    await _loadComments();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_comments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No reviews yet. Be the first to review!',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Reviews (${_comments.length})',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _comments.length,
          itemBuilder: (context, index) {
            final commentData = _comments[index].data() as Map<String, dynamic>;
            return FadeInWidget(
              delay: Duration(milliseconds: 100 * index),
              child: CommentCard(
                commentData: commentData,
                isCurrentUser: commentData['userId'] == widget.currentUserId,
                ratingId: _comments[index].id,
                onRefresh: _loadComments,
              ),
            );
          },
        ),
      ],
    );
  }
}

class CommentCard extends StatelessWidget {
  final Map<String, dynamic> commentData;
  final bool isCurrentUser;
  final String ratingId;
  final VoidCallback? onRefresh;

  const CommentCard({
    Key? key,
    required this.commentData,
    required this.isCurrentUser,
    required this.ratingId,
    this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final userId = commentData['userId'] as String? ?? '';

    return FutureBuilder<Map<String, dynamic>>(
      future: UserServiceFixed.getUserProfile(userId),
      builder: (context, snapshot) {
        final userProfile = snapshot.data ?? {};
        final profileName = userProfile['name'] as String?;
        final photoBase64 = userProfile['photoBase64'] as String?;

        // User requested to show name instead of "YOU"
        // Use profile name if available, otherwise fallback to comment data
        final displayName =
            profileName ?? commentData['userName'] ?? 'Anonymous';

        final rating = (commentData['rating'] ?? 0.0).toDouble();
        final comment = commentData['comment'] ?? '';
        final createdAt = commentData['createdAt'] as Timestamp?;
        final formattedDate = createdAt != null
            ? DateFormat('MMM dd, yyyy - hh:mm a').format(createdAt.toDate())
            : 'Recently';

        return AnimatedCard(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          onPressed: isCurrentUser ? () => _showCommentOptions(context) : null,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          Theme.of(context).primaryColor.withOpacity(0.1),
                      backgroundImage:
                          photoBase64 != null && photoBase64.isNotEmpty
                              ? MemoryImage(base64Decode(photoBase64))
                              : null,
                      child: photoBase64 == null || photoBase64.isEmpty
                          ? Text(
                              displayName.isNotEmpty
                                  ? displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    // Name and Options
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (isCurrentUser)
                            const Icon(Icons.more_vert,
                                size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ...List.generate(5, (index) {
                      return Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 16,
                      );
                    }),
                    const SizedBox(width: 8),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
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
                const SizedBox(height: 4),
                Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                if (isCurrentUser)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Tap to edit',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCommentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Comment Options',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Edit Comment'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Comment'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteRating(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context) {
    final TextEditingController commentController =
        TextEditingController(text: commentData['comment']);
    double currentRating = (commentData['rating'] ?? 0.0).toDouble();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Review'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < currentRating
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () {
                          setState(() {
                            currentRating = (index + 1).toDouble();
                          });
                        },
                      );
                    }),
                  ),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Leave a comment (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .collection('station_ratings')
                        .doc(ratingId)
                        .update({
                      'rating': currentRating,
                      'comment': commentController.text.trim(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    Navigator.pop(context);
                    if (onRefresh != null) {
                      onRefresh!();
                    }
                  },
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteRating(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Review'),
          content: const Text('Are you sure you want to delete this review?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('station_ratings')
                    .doc(ratingId)
                    .delete();
                Navigator.pop(context);
                if (onRefresh != null) {
                  onRefresh!();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
