import React, { useState, useEffect } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

export default function AdminDashboard() {
  const [washrooms, setWashrooms] = useState([]);
  const [selectedWashroom, setSelectedWashroom] = useState(null);
  const [historicalData, setHistoricalData] = useState([]);
  const [stats, setStats] = useState({
    avgScore: 0,
    totalAlerts: 0,
    cleaningsToday: 0,
    activeWashrooms: 0
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Firebase configuration (replace with your values)
  const FIREBASE_CONFIG = {
    databaseURL: "https://YOUR_PROJECT.firebaseio.com",
    apiKey: "YOUR_API_KEY",
    projectId: "YOUR_PROJECT_ID"
  };

  useEffect(() => {
    // Simulate real-time data updates
    loadMockData();
    
    // In production, you would connect to Firebase REST API or WebSocket
    // For demo purposes, we'll refresh every 10 seconds
    const interval = setInterval(loadMockData, 10000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (selectedWashroom) {
      loadHistoricalData(selectedWashroom);
    }
  }, [selectedWashroom]);

  const loadMockData = () => {
    // Mock data for demonstration
    // In production, fetch from Firebase REST API:
    // fetch(`${FIREBASE_CONFIG.databaseURL}/washrooms.json?auth=${FIREBASE_CONFIG.apiKey}`)
    
    const mockWashrooms = [
      {
        id: 'WR_001',
        score: 78,
        timestamp: new Date().toISOString(),
        component_scores: {
          air_quality: 85,
          floor_moisture: 92,
          humidity: 78,
          temperature: 95
        },
        anomalies: []
      },
      {
        id: 'WR_002',
        score: 45,
        timestamp: new Date().toISOString(),
        component_scores: {
          air_quality: 42,
          floor_moisture: 65,
          humidity: 45,
          temperature: 88
        },
        anomalies: [
          { type: 'ODOR_SPIKE', severity: 'HIGH', message: 'Severe odor detected' }
        ]
      },
      {
        id: 'WR_003',
        score: 92,
        timestamp: new Date().toISOString(),
        component_scores: {
          air_quality: 95,
          floor_moisture: 98,
          humidity: 88,
          temperature: 92
        },
        anomalies: []
      }
    ];

    setWashrooms(mockWashrooms);
    
    const avgScore = mockWashrooms.reduce((sum, w) => sum + w.score, 0) / mockWashrooms.length;
    const totalAlerts = mockWashrooms.reduce((sum, w) => sum + w.anomalies.length, 0);
    
    setStats({
      avgScore: avgScore.toFixed(1),
      totalAlerts,
      cleaningsToday: 3,
      activeWashrooms: mockWashrooms.length
    });
    
    setLoading(false);
  };

  const loadHistoricalData = (washroomId) => {
    // Mock historical data
    // In production: fetch from Firestore REST API
    const now = new Date();
    const data = Array.from({ length: 20 }, (_, i) => {
      const time = new Date(now.getTime() - (20 - i) * 60000);
      return {
        time: time.toLocaleTimeString(),
        score: Math.max(40, Math.min(95, 70 + Math.sin(i / 3) * 15 + Math.random() * 10)),
        airQuality: Math.max(30, Math.min(100, 75 + Math.cos(i / 2) * 20)),
        moisture: Math.max(20, Math.min(100, 80 + Math.sin(i / 4) * 15)),
      };
    });
    
    setHistoricalData(data);
  };

  const getScoreColor = (score) => {
    if (score >= 70) return '#10b981';
    if (score >= 50) return '#f59e0b';
    return '#ef4444';
  };

  // Firebase REST API helper functions for production use
  const fetchFromFirebase = async (path) => {
    try {
      const response = await fetch(
        `${FIREBASE_CONFIG.databaseURL}${path}.json?auth=${FIREBASE_CONFIG.apiKey}`
      );
      return await response.json();
    } catch (err) {
      setError('Failed to fetch data');
      return null;
    }
  };

  const subscribeToRealtimeUpdates = (path, callback) => {
    // For real-time updates, use Server-Sent Events (SSE)
    const eventSource = new EventSource(
      `${FIREBASE_CONFIG.databaseURL}${path}.json?auth=${FIREBASE_CONFIG.apiKey}`
    );
    
    eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);
      callback(data);
    };
    
    return () => eventSource.close();
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-900 text-white flex items-center justify-center">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500 mb-4"></div>
          <p className="text-xl">Loading Dashboard...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-900 text-white p-6">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-4xl font-bold mb-2">🚻 Hygiene Analytics Dashboard</h1>
        <p className="text-gray-400">Real-time washroom hygiene monitoring and analytics</p>
        {error && (
          <div className="mt-4 bg-red-900 bg-opacity-30 border border-red-500 rounded-lg p-3 text-red-300">
            {error}
          </div>
        )}
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
        <StatCard
          title="Average Score"
          value={`${stats.avgScore}%`}
          icon="📊"
          color="blue"
        />
        <StatCard
          title="Active Washrooms"
          value={stats.activeWashrooms}
          icon="🚻"
          color="green"
        />
        <StatCard
          title="Active Alerts"
          value={stats.totalAlerts}
          icon="⚠️"
          color="red"
        />
        <StatCard
          title="Cleanings Today"
          value={stats.cleaningsToday}
          icon="🧹"
          color="purple"
        />
      </div>

      {/* Main Content Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Washroom List */}
        <div className="lg:col-span-1 bg-gray-800 rounded-lg p-6">
          <h2 className="text-2xl font-bold mb-4">Washrooms</h2>
          <div className="space-y-3 max-h-96 overflow-y-auto">
            {washrooms.map(washroom => (
              <div
                key={washroom.id}
                onClick={() => setSelectedWashroom(washroom.id)}
                className={`p-4 rounded-lg cursor-pointer transition-all ${
                  selectedWashroom === washroom.id
                    ? 'bg-blue-600'
                    : 'bg-gray-700 hover:bg-gray-650'
                }`}
              >
                <div className="flex justify-between items-start mb-2">
                  <div>
                    <h3 className="font-semibold">{washroom.id}</h3>
                    <p className="text-sm text-gray-400">
                      {new Date(washroom.timestamp).toLocaleTimeString()}
                    </p>
                  </div>
                  <div className="text-right">
                    <div
                      className="text-2xl font-bold"
                      style={{ color: getScoreColor(washroom.score) }}
                    >
                      {Math.round(washroom.score)}%
                    </div>
                  </div>
                </div>
                
                {washroom.anomalies && washroom.anomalies.length > 0 && (
                  <div className="mt-2 text-xs text-red-400">
                    ⚠️ {washroom.anomalies.length} anomaly/ies
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>

        {/* Charts and Details */}
        <div className="lg:col-span-2 space-y-6">
          {/* Historical Trend Chart */}
          <div className="bg-gray-800 rounded-lg p-6">
            <h2 className="text-2xl font-bold mb-4">
              {selectedWashroom ? `${selectedWashroom} - Historical Trend` : 'Select a Washroom'}
            </h2>
            {historicalData.length > 0 ? (
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={historicalData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
                  <XAxis dataKey="time" stroke="#9ca3af" />
                  <YAxis stroke="#9ca3af" />
                  <Tooltip
                    contentStyle={{ backgroundColor: '#1f2937', border: 'none' }}
                  />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="score"
                    stroke="#3b82f6"
                    strokeWidth={2}
                    name="Hygiene Score"
                  />
                  <Line
                    type="monotone"
                    dataKey="airQuality"
                    stroke="#10b981"
                    strokeWidth={2}
                    name="Air Quality"
                  />
                  <Line
                    type="monotone"
                    dataKey="moisture"
                    stroke="#f59e0b"
                    strokeWidth={2}
                    name="Floor Moisture"
                  />
                </LineChart>
              </ResponsiveContainer>
            ) : (
              <div className="h-300 flex items-center justify-center text-gray-500">
                Select a washroom to view historical data
              </div>
            )}
          </div>

          {/* Component Scores */}
          {selectedWashroom && washrooms.find(w => w.id === selectedWashroom) && (
            <div className="bg-gray-800 rounded-lg p-6">
              <h2 className="text-2xl font-bold mb-4">Component Breakdown</h2>
              <div className="grid grid-cols-2 gap-4">
                {Object.entries(
                  washrooms.find(w => w.id === selectedWashroom)?.component_scores || {}
                ).map(([key, value]) => (
                  <div key={key} className="bg-gray-700 rounded-lg p-4">
                    <div className="text-sm text-gray-400 mb-1 capitalize">
                      {key.replace('_', ' ')}
                    </div>
                    <div
                      className="text-3xl font-bold"
                      style={{ color: getScoreColor(value) }}
                    >
                      {Math.round(value)}%
                    </div>
                    <div className="mt-2 h-2 bg-gray-600 rounded-full overflow-hidden">
                      <div
                        className="h-full rounded-full transition-all"
                        style={{
                          width: `${value}%`,
                          backgroundColor: getScoreColor(value)
                        }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Anomalies */}
          {selectedWashroom && washrooms.find(w => w.id === selectedWashroom)?.anomalies?.length > 0 && (
            <div className="bg-gray-800 rounded-lg p-6">
              <h2 className="text-2xl font-bold mb-4 text-red-400">⚠️ Active Anomalies</h2>
              <div className="space-y-3">
                {washrooms.find(w => w.id === selectedWashroom).anomalies.map((anomaly, idx) => (
                  <div key={idx} className="bg-red-900 bg-opacity-20 border border-red-500 rounded-lg p-4">
                    <div className="flex justify-between items-start">
                      <div>
                        <div className="font-semibold text-red-400">{anomaly.type}</div>
                        <div className="text-sm text-gray-300 mt-1">{anomaly.message}</div>
                      </div>
                      <span className={`px-3 py-1 rounded-full text-xs font-semibold ${
                        anomaly.severity === 'HIGH' ? 'bg-red-600' :
                        anomaly.severity === 'MEDIUM' ? 'bg-orange-600' : 'bg-yellow-600'
                      }`}>
                        {anomaly.severity}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Firebase API Integration Instructions */}
      <div className="mt-8 bg-gray-800 rounded-lg p-6">
        <h3 className="text-xl font-bold mb-3">🔧 Firebase Integration Guide</h3>
        <div className="text-sm text-gray-400 space-y-2">
          <p><strong>This dashboard uses mock data for demonstration.</strong> To connect to real Firebase:</p>
          <ol className="list-decimal list-inside space-y-1 ml-4">
            <li>Update FIREBASE_CONFIG with your project credentials</li>
            <li>Replace loadMockData() with fetchFromFirebase('/washrooms')</li>
            <li>Use subscribeToRealtimeUpdates() for live data streaming</li>
            <li>Deploy using: npm run build && firebase deploy --only hosting</li>
          </ol>
          <p className="mt-3 p-3 bg-blue-900 bg-opacity-20 border border-blue-500 rounded">
            <strong>Note:</strong> Firebase libraries are not available in this environment, but the REST API works in production deployments.
          </p>
        </div>
      </div>
    </div>
  );
}

function StatCard({ title, value, icon, color }) {
  const colorClasses = {
    blue: 'from-blue-600 to-blue-700',
    green: 'from-green-600 to-green-700',
    red: 'from-red-600 to-red-700',
    purple: 'from-purple-600 to-purple-700',
  };

  return (
    <div className={`bg-gradient-to-br ${colorClasses[color]} rounded-lg p-6`}>
      <div className="flex items-center justify-between mb-2">
        <div className="text-4xl">{icon}</div>
        <div className="text-3xl font-bold">{value}</div>
      </div>
      <div className="text-sm opacity-90">{title}</div>
    </div>
  );
}
