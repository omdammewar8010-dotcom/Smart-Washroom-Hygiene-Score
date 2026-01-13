import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(CleanerApp());
}

class CleanerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hygiene Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: CleanerDashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CleanerDashboard extends StatefulWidget {
  @override
  _CleanerDashboardState createState() => _CleanerDashboardState();
}

class _CleanerDashboardState extends State<CleanerDashboard> {
  final DatabaseReference _realtimeDb = FirebaseDatabase.instance.ref();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  List<WashroomData> _washrooms = [];
  List<NotificationData> _notifications = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _setupFirebaseMessaging();
    _loadWashrooms();
    _listenToNotifications();
  }
  
  void _setupFirebaseMessaging() async {
    // Request permission
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    
    // Get FCM token
    String? token = await _messaging.getToken();
    print('FCM Token: $token');
    
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Notification received: ${message.notification?.title}');
      _showLocalNotification(message);
    });
  }
  
  void _showLocalNotification(RemoteMessage message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.notification?.body ?? 'New notification'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            // Navigate to notifications
          },
        ),
      ),
    );
  }
  
  void _loadWashrooms() async {
    setState(() => _isLoading = true);
    
    // Get washroom configurations
    final configs = await _firestore.collection('washroom_configs').get();
    
    List<WashroomData> washrooms = [];
    
    for (var doc in configs.docs) {
      final config = doc.data();
      final washroomId = doc.id;
      
      // Get current status from Realtime Database
      final snapshot = await _realtimeDb.child('washrooms/$washroomId/current').get();
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        washrooms.add(WashroomData(
          id: washroomId,
          name: config['name'] ?? 'Washroom $washroomId',
          location: config['location'] ?? 'Unknown',
          score: (data['score'] ?? 0).toDouble(),
          timestamp: data['timestamp'] ?? '',
          anomalies: List<Map<String, dynamic>>.from(
            (data['anomalies'] ?? []).map((e) => Map<String, dynamic>.from(e))
          ),
        ));
      }
    }
    
    // Sort by score (lowest first - needs attention)
    washrooms.sort((a, b) => a.score.compareTo(b.score));
    
    setState(() {
      _washrooms = washrooms;
      _isLoading = false;
    });
  }
  
  void _listenToNotifications() {
    _realtimeDb.child('notifications').onChildAdded.listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        
        setState(() {
          _notifications.insert(0, NotificationData(
            washroomId: data['washroom_id'] ?? '',
            message: data['message'] ?? '',
            timestamp: data['timestamp'] ?? '',
            type: data['type'] ?? 'INFO',
            score: (data['score'] ?? 0).toDouble(),
          ));
        });
        
        // Keep only last 50 notifications
        if (_notifications.length > 50) {
          _notifications.removeLast();
        }
      }
    });
  }
  
  void _markCleaned(String washroomId) async {
    // Show confirmation dialog
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Cleaning'),
        content: Text('Mark this washroom as cleaned?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('CONFIRM'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      // Update cleaning timestamp
      await _realtimeDb.child('washrooms/$washroomId/last_cleaned').set({
        'timestamp': DateTime.now().toIso8601String(),
        'cleaner': 'Mobile App User', // Can be replaced with actual user
      });
      
      // Clear notifications for this washroom
      await _realtimeDb.child('notifications/$washroomId').remove();
      
      // Reload data
      _loadWashrooms();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Washroom marked as cleaned!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hygiene Monitor'),
        actions: [
          IconBadge(
            count: _notifications.where((n) => n.type == 'HYGIENE_ALERT').length,
            child: IconButton(
              icon: Icon(Icons.notifications),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NotificationsPage(notifications: _notifications),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadWashrooms,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _loadWashrooms(),
              child: _washrooms.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 80, color: Colors.grey),
                          SizedBox(height: 20),
                          Text(
                            'No washrooms configured',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _washrooms.length,
                      padding: EdgeInsets.all(10),
                      itemBuilder: (context, index) {
                        return WashroomCard(
                          data: _washrooms[index],
                          onCleanPressed: () => _markCleaned(_washrooms[index].id),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WashroomDetailPage(
                                  washroomId: _washrooms[index].id,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
    );
  }
}

class WashroomCard extends StatelessWidget {
  final WashroomData data;
  final VoidCallback onCleanPressed;
  final VoidCallback onTap;
  
  WashroomCard({
    required this.data,
    required this.onCleanPressed,
    required this.onTap,
  });
  
  Color _getScoreColor(double score) {
    if (score >= 70) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }
  
  String _getScoreLabel(double score) {
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Needs Cleaning';
  }
  
  @override
  Widget build(BuildContext context) {
    final color = _getScoreColor(data.score);
    
    return Card(
      elevation: 4,
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: color.withOpacity(0.5),
              width: 2,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.wc, color: color, size: 30),
                    ),
                    SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            data.location,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${data.score.toInt()}%',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        Text(
                          _getScoreLabel(data.score),
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                
                if (data.anomalies.isNotEmpty) ...[
                  SizedBox(height: 15),
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text(
                              '${data.anomalies.length} Anomalies',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        ...data.anomalies.take(2).map((a) => Padding(
                          padding: EdgeInsets.only(left: 26, top: 5),
                          child: Text(
                            '• ${a['message']}',
                            style: TextStyle(fontSize: 12, color: Colors.red[700]),
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
                
                SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(data.timestamp),
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    ElevatedButton.icon(
                      onPressed: onCleanPressed,
                      icon: Icon(Icons.cleaning_services, size: 18),
                      label: Text('Mark Cleaned'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  String _formatTime(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dt);
      
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (e) {
      return 'Unknown';
    }
  }
}

class WashroomDetailPage extends StatelessWidget {
  final String washroomId;
  
  WashroomDetailPage({required this.washroomId});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Washroom Details'),
      ),
      body: StreamBuilder(
        stream: FirebaseDatabase.instance
            .ref('washrooms/$washroomId/current')
            .onValue,
        builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.data?.snapshot.value == null) {
            return Center(child: Text('No data available'));
          }
          
          final data = Map<String, dynamic>.from(
            snapshot.data!.snapshot.value as Map
          );
          
          return SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Score display
                // Component scores
                // Historical trends (can add chart)
                // Cleaning log
              ],
            ),
          );
        },
      ),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  final List<NotificationData> notifications;
  
  NotificationsPage({required this.notifications});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications'),
      ),
      body: notifications.isEmpty
          ? Center(child: Text('No notifications'))
          : ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notif = notifications[index];
                return ListTile(
                  leading: Icon(
                    notif.type == 'HYGIENE_ALERT' ? Icons.warning : Icons.info,
                    color: notif.type == 'HYGIENE_ALERT' ? Colors.red : Colors.blue,
                  ),
                  title: Text(notif.message),
                  subtitle: Text(notif.washroomId),
                  trailing: Text(_formatTime(notif.timestamp)),
                );
              },
            ),
    );
  }
  
  String _formatTime(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}

class IconBadge extends StatelessWidget {
  final int count;
  final Widget child;
  
  IconBadge({required this.count, required this.child});
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (count > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                count > 9 ? '9+' : count.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class WashroomData {
  final String id;
  final String name;
  final String location;
  final double score;
  final String timestamp;
  final List<Map<String, dynamic>> anomalies;
  
  WashroomData({
    required this.id,
    required this.name,
    required this.location,
    required this.score,
    required this.timestamp,
    required this.anomalies,
  });
}

class NotificationData {
  final String washroomId;
  final String message;
  final String timestamp;
  final String type;
  final double score;
  
  NotificationData({
    required this.washroomId,
    required this.message,
    required this.timestamp,
    required this.type,
    required this.score,
  });
}
