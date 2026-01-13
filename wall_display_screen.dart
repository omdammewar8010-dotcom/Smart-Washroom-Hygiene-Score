import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(WallDisplayApp());
}

class WallDisplayApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Washroom Hygiene Display',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
      ),
      home: WallDisplay(washroomId: 'WR_001'), // Configure per washroom
      debugShowCheckedModeBanner: false,
    );
  }
}

class WallDisplay extends StatefulWidget {
  final String washroomId;

  WallDisplay({required this.washroomId});

  @override
  _WallDisplayState createState() => _WallDisplayState();
}

class _WallDisplayState extends State<WallDisplay> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  double _hygieneScore = 0;
  Map<String, dynamic> _componentScores = {};
  List<dynamic> _anomalies = [];
  String _lastUpdated = '';
  bool _isConnected = true;

  late AnimationController _pulseController;
  late AnimationController _scoreController;
  late Animation<double> _scoreAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _scoreController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );

    _scoreAnimation = Tween<double>(begin: 0, end: _hygieneScore)
        .animate(CurvedAnimation(parent: _scoreController, curve: Curves.easeOutCubic));

    _listenToRealtimeData();
  }

  void _listenToRealtimeData() {
    _database.child('washrooms/${widget.washroomId}/current').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);

        setState(() {
          double newScore = (data['score'] ?? 0).toDouble();

          // Animate score change
          _scoreAnimation = Tween<double>(
            begin: _hygieneScore,
            end: newScore,
          ).animate(CurvedAnimation(parent: _scoreController, curve: Curves.easeOutCubic));

          _scoreController.forward(from: 0);

          _hygieneScore = newScore;
          _componentScores = data['component_scores'] ?? {};
          _anomalies = data['anomalies'] ?? [];
          _lastUpdated = _formatTimestamp(data['timestamp'] ?? '');
          _isConnected = true;
        });
      }
    });

    // Check connection status
    _database.child('.info/connected').onValue.listen((event) {
      setState(() {
        _isConnected = event.snapshot.value as bool? ?? false;
      });
    });
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  Color _getScoreColor(double score) {
    if (score >= 70) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  String _getScoreLabel(double score) {
    if (score >= 90) return 'EXCELLENT';
    if (score >= 70) return 'GOOD';
    if (score >= 50) return 'FAIR';
    if (score >= 30) return 'POOR';
    return 'CRITICAL';
  }

  IconData _getScoreIcon(double score) {
    if (score >= 70) return Icons.sentiment_very_satisfied;
    if (score >= 50) return Icons.sentiment_neutral;
    return Icons.sentiment_very_dissatisfied;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              _getScoreColor(_hygieneScore).withOpacity(0.1),
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildMainScore()),
              _buildComponentScores(),
              _buildAnomalies(),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.wc, size: 40, color: Colors.white70),
              SizedBox(width: 15),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WASHROOM HYGIENE',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    'ID: ${widget.washroomId}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              if (!_isConnected)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('OFFLINE', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                )
              else
                FadeTransition(
                  opacity: _pulseController,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.circle, color: Colors.green, size: 12),
                        SizedBox(width: 8),
                        Text('LIVE', style: TextStyle(color: Colors.green)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainScore() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _scoreAnimation,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Glow effect
                  Container(
                    width: 350,
                    height: 350,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _getScoreColor(_scoreAnimation.value).withOpacity(0.5),
                          blurRadius: 100,
                          spreadRadius: 30,
                        ),
                      ],
                    ),
                  ),
                  // Main circle
                  Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _getScoreColor(_scoreAnimation.value),
                        width: 12,
                      ),
                      gradient: RadialGradient(
                        colors: [
                          _getScoreColor(_scoreAnimation.value).withOpacity(0.1),
                          Colors.black,
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getScoreIcon(_scoreAnimation.value),
                          size: 80,
                          color: _getScoreColor(_scoreAnimation.value),
                        ),
                        SizedBox(height: 20),
                        Text(
                          '${_scoreAnimation.value.toInt()}%',
                          style: TextStyle(
                            fontSize: 90,
                            fontWeight: FontWeight.bold,
                            color: _getScoreColor(_scoreAnimation.value),
                            shadows: [
                              Shadow(
                                color: _getScoreColor(_scoreAnimation.value).withOpacity(0.5),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _getScoreLabel(_scoreAnimation.value),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w300,
                            color: Colors.white70,
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildComponentScores() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildComponentCard('Air Quality', _componentScores['air_quality']?.toDouble() ?? 0, Icons.air),
          _buildComponentCard('Floor', _componentScores['floor_moisture']?.toDouble() ?? 0, Icons.water_drop),
          _buildComponentCard('Humidity', _componentScores['humidity']?.toDouble() ?? 0, Icons.opacity),
          _buildComponentCard('Temperature', _componentScores['temperature']?.toDouble() ?? 0, Icons.thermostat),
        ],
      ),
    );
  }

  Widget _buildComponentCard(String label, double value, IconData icon) {
    return Container(
      width: 140,
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: _getScoreColor(value).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: _getScoreColor(value), size: 30),
          SizedBox(height: 10),
          Text(
            '${value.toInt()}%',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _getScoreColor(value),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnomalies() {
    if (_anomalies.isEmpty) return SizedBox.shrink();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 10),
              Text(
                'ANOMALIES DETECTED',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          ..._anomalies.take(3).map((anomaly) {
            final anomalyData = Map<String, dynamic>.from(anomaly);
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      anomalyData['message'] ?? 'Unknown anomaly',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Last Updated: $_lastUpdated',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
          Text(
            '© Smart Hygiene IoT System',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scoreController.dispose();
    super.dispose();
  }
}
