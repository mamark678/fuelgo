import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notificationsRef = FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<QuerySnapshot>(
        stream: notificationsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No notifications yet'));
          }

          final docs = snapshot.data!.docs;
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final title = data['title'] ?? '';
              final body = data['body'] ?? '';
              final station = data['stationName'] ?? '';
              final timestamp = data['createdAt'] as Timestamp?;
              final read = data['read'] ?? false;
              final type = data['type'] as String?;
              final itemId = data['itemId'] as String?;

              return ListTile(
                tileColor: read ? null : Colors.grey.shade100,
                title: Text(title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (station.isNotEmpty)
                      Text(station, style: const TextStyle(fontSize: 12)),
                    Text(body),
                    if (timestamp != null)
                      Text(
                        DateTime.fromMillisecondsSinceEpoch(
                                timestamp.millisecondsSinceEpoch)
                            .toLocal()
                            .toString(),
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
                onTap: () async {
                  // Mark as read
                  if (!read) {
                    await doc.reference
                        .set({'read': true}, SetOptions(merge: true));
                  }

                  // Navigate to For You page if it's an offer or voucher
                  if ((type == 'offer' || type == 'voucher') &&
                      itemId != null &&
                      itemId.isNotEmpty) {
                    // Navigate to For You tab and highlight the item
                    // Pass the highlight info through Navigator result
                    Navigator.of(context).pop({
                      'highlightItemId': itemId,
                      'highlightType': type,
                      'tabIndex': 0, // For You tab is at index 0
                    });
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
