import firebase_admin
from firebase_admin import credentials, firestore, db
import paho.mqtt.client as mqtt
import json
import csv
from datetime import datetime, timedelta
import threading
import time
import os
from collections import defaultdict
import statistics

# Firebase Configuration
cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred, {
    'databaseURL': 'https://YOUR-PROJECT-ID.firebaseio.com'
})

firestore_db = firestore.client()
realtime_db = db.reference()

# MQTT Configuration
MQTT_BROKER = "broker.hivemq.com"
MQTT_PORT = 1883
MQTT_TOPIC = "washroom/hygiene/data"
MQTT_CLIENT_ID = "hygiene_backend_processor"

# System Configuration
HYGIENE_THRESHOLD = 50  # Alert if below this
DECAY_RATE = 0.5  # Score decay per hour without cleaning
MAX_DECAY_HOURS = 8
CSV_LOG_DIR = "hygiene_logs"

# Adaptive Weighting Profiles
WEIGHT_PROFILES = {
    'office': {
        'air_quality': 0.30,
        'floor_moisture': 0.25,
        'humidity': 0.20,
        'temperature': 0.15,
        'footfall_density': 0.10
    },
    'public': {
        'air_quality': 0.35,
        'floor_moisture': 0.30,
        'humidity': 0.15,
        'temperature': 0.10,
        'footfall_density': 0.10
    },
    'hospital': {
        'air_quality': 0.40,
        'floor_moisture': 0.30,
        'humidity': 0.20,
        'temperature': 0.05,
        'footfall_density': 0.05
    },
    'restaurant': {
        'air_quality': 0.35,
        'floor_moisture': 0.25,
        'humidity': 0.20,
        'temperature': 0.15,
        'footfall_density': 0.05
    }
}

# Washroom Configuration (stored in database, cached here)
washroom_configs = {}
last_cleaning_times = {}
last_scores = {}
anomaly_buffer = defaultdict(list)

class HygieneScoreEngine:
    def __init__(self, washroom_id, profile='public'):
        self.washroom_id = washroom_id
        self.profile = profile
        self.weights = WEIGHT_PROFILES.get(profile, WEIGHT_PROFILES['public'])
        
    def calculate_component_scores(self, data):
        """Convert raw sensor values to 0-100 scores (higher is better)"""
        scores = {}
        
        # Air Quality (MQ135 - lower is better, invert)
        air_quality_raw = data.get('air_quality', 50)
        scores['air_quality'] = max(0, 100 - air_quality_raw)
        
        # Floor Moisture (lower is better, invert)
        moisture_raw = data.get('floor_moisture', 30)
        scores['floor_moisture'] = max(0, 100 - moisture_raw)
        
        # Humidity (optimal range 40-60%)
        humidity = data.get('humidity', 50)
        if 40 <= humidity <= 60:
            scores['humidity'] = 100
        elif humidity < 40:
            scores['humidity'] = max(0, humidity * 2.5)  # Scale 0-40 to 0-100
        else:
            scores['humidity'] = max(0, 100 - (humidity - 60) * 2)  # Penalize >60
        
        # Temperature (optimal range 20-26°C)
        temperature = data.get('temperature', 23)
        if 20 <= temperature <= 26:
            scores['temperature'] = 100
        elif temperature < 20:
            scores['temperature'] = max(0, temperature * 5)
        else:
            scores['temperature'] = max(0, 100 - (temperature - 26) * 5)
        
        # Footfall Density (usage intensity - higher usage needs more attention)
        footfall = data.get('footfall_count', 0)
        # Assume max 100 people per hour for normalization
        footfall_score = max(0, 100 - (footfall / 100) * 100)
        scores['footfall_density'] = footfall_score
        
        return scores
    
    def calculate_weighted_score(self, component_scores):
        """Calculate weighted hygiene score"""
        total_score = 0
        for component, score in component_scores.items():
            weight = self.weights.get(component, 0)
            total_score += score * weight
        
        return round(total_score, 2)
    
    def apply_time_decay(self, base_score, last_cleaned):
        """Apply decay based on time since last cleaning"""
        if not last_cleaned:
            return base_score
        
        hours_since_cleaning = (datetime.now() - last_cleaned).total_seconds() / 3600
        
        if hours_since_cleaning <= 1:
            return base_score
        
        decay_hours = min(hours_since_cleaning - 1, MAX_DECAY_HOURS)
        decay_amount = decay_hours * DECAY_RATE
        
        decayed_score = max(0, base_score - decay_amount)
        return round(decayed_score, 2)
    
    def detect_anomalies(self, data, component_scores):
        """Detect various anomalies"""
        anomalies = []
        
        # High air quality reading (poor air)
        if data.get('air_quality', 0) > 70:
            anomalies.append({
                'type': 'ODOR_SPIKE',
                'severity': 'HIGH',
                'message': 'Severe odor/ammonia levels detected',
                'value': data.get('air_quality')
            })
        
        # High floor moisture (leak or water overflow)
        if data.get('floor_moisture', 0) > 60:
            anomalies.append({
                'type': 'MOISTURE_ALERT',
                'severity': 'HIGH',
                'message': 'Wet floor or potential leakage detected',
                'value': data.get('floor_moisture')
            })
        
        # Extreme temperature
        temp = data.get('temperature', 23)
        if temp < 10 or temp > 35:
            anomalies.append({
                'type': 'TEMPERATURE_ANOMALY',
                'severity': 'MEDIUM',
                'message': f'Unusual temperature: {temp}°C',
                'value': temp
            })
        
        # High footfall without score recovery (cleaning needed)
        if data.get('footfall_count', 0) > 50 and component_scores.get('air_quality', 100) < 40:
            anomalies.append({
                'type': 'HIGH_USAGE',
                'severity': 'MEDIUM',
                'message': 'High usage detected, cleaning recommended',
                'value': data.get('footfall_count')
            })
        
        return anomalies

class BackendProcessor:
    def __init__(self):
        self.mqtt_client = mqtt.Client(MQTT_CLIENT_ID)
        self.mqtt_client.on_connect = self.on_mqtt_connect
        self.mqtt_client.on_message = self.on_mqtt_message
        self.running = True
        
        # Create CSV log directory
        os.makedirs(CSV_LOG_DIR, exist_ok=True)
        
        # Start background tasks
        threading.Thread(target=self.daily_csv_logger, daemon=True).start()
        threading.Thread(target=self.console_dashboard, daemon=True).start()
        
    def on_mqtt_connect(self, client, userdata, flags, rc):
        print(f"✓ Connected to MQTT broker (Code: {rc})")
        client.subscribe(MQTT_TOPIC)
        client.subscribe("washroom/+/heartbeat")
        
    def on_mqtt_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())
            
            if 'type' in payload and payload['type'] == 'heartbeat':
                self.handle_heartbeat(payload)
            else:
                self.process_sensor_data(payload)
                
        except Exception as e:
            print(f"✗ Error processing message: {e}")
    
    def handle_heartbeat(self, data):
        """Process heartbeat to detect sensor failures"""
        washroom_id = data.get('washroom_id')
        
        # Update last heartbeat time
        realtime_db.child(f'washrooms/{washroom_id}/last_heartbeat').set({
            'timestamp': datetime.now().isoformat(),
            'uptime_ms': data.get('uptime_ms'),
            'free_heap': data.get('free_heap'),
            'wifi_connected': data.get('wifi_connected')
        })
        
    def process_sensor_data(self, data):
        """Main processing pipeline"""
        washroom_id = data.get('washroom_id')
        
        if not washroom_id:
            print("✗ Missing washroom_id in data")
            return
        
        # Get washroom configuration
        config = self.get_washroom_config(washroom_id)
        profile = config.get('profile', 'public')
        
        # Initialize score engine
        engine = HygieneScoreEngine(washroom_id, profile)
        
        # Calculate component scores
        component_scores = engine.calculate_component_scores(data)
        
        # Calculate base weighted score
        base_score = engine.calculate_weighted_score(component_scores)
        
        # Apply time decay
        last_cleaned = last_cleaning_times.get(washroom_id)
        final_score = engine.apply_time_decay(base_score, last_cleaned)
        
        # Detect anomalies
        anomalies = engine.detect_anomalies(data, component_scores)
        
        # Prepare result
        result = {
            'washroom_id': washroom_id,
            'timestamp': datetime.now().isoformat(),
            'sensor_data': data,
            'component_scores': component_scores,
            'base_score': base_score,
            'final_score': final_score,
            'decay_applied': base_score - final_score,
            'anomalies': anomalies,
            'profile': profile
        }
        
        # Store in Firebase
        self.store_in_firebase(result)
        
        # Check for alerts
        self.check_alerts(result)
        
        # Update cache
        last_scores[washroom_id] = final_score
        
        # Console output
        print(f"\n{'='*60}")
        print(f"🚻 Washroom: {washroom_id} | Profile: {profile}")
        print(f"📊 Hygiene Score: {final_score}% (Base: {base_score}%)")
        print(f"🔍 Components: AQ={component_scores['air_quality']:.1f}% | "
              f"Moist={component_scores['floor_moisture']:.1f}% | "
              f"Humid={component_scores['humidity']:.1f}%")
        if anomalies:
            print(f"⚠️  Anomalies: {len(anomalies)}")
            for anomaly in anomalies:
                print(f"   - {anomaly['type']}: {anomaly['message']}")
        print(f"{'='*60}\n")
        
    def get_washroom_config(self, washroom_id):
        """Get washroom configuration from cache or database"""
        if washroom_id not in washroom_configs:
            doc = firestore_db.collection('washroom_configs').document(washroom_id).get()
            if doc.exists:
                washroom_configs[washroom_id] = doc.to_dict()
            else:
                # Create default config
                default_config = {
                    'profile': 'public',
                    'threshold': HYGIENE_THRESHOLD,
                    'name': f'Washroom {washroom_id}',
                    'location': 'Unknown'
                }
                firestore_db.collection('washroom_configs').document(washroom_id).set(default_config)
                washroom_configs[washroom_id] = default_config
        
        return washroom_configs[washroom_id]
    
    def store_in_firebase(self, result):
        """Store processed data in Firebase"""
        washroom_id = result['washroom_id']
        timestamp = result['timestamp']
        
        # Store in Firestore (historical data)
        firestore_db.collection('hygiene_logs').add(result)
        
        # Update real-time database (current state)
        realtime_db.child(f'washrooms/{washroom_id}/current').set({
            'score': result['final_score'],
            'timestamp': timestamp,
            'component_scores': result['component_scores'],
            'anomalies': result['anomalies']
        })
        
    def check_alerts(self, result):
        """Check if alerts need to be triggered"""
        washroom_id = result['washroom_id']
        score = result['final_score']
        
        config = self.get_washroom_config(washroom_id)
        threshold = config.get('threshold', HYGIENE_THRESHOLD)
        
        if score < threshold:
            self.send_cleaner_notification(washroom_id, score, result['anomalies'])
    
    def send_cleaner_notification(self, washroom_id, score, anomalies):
        """Send notification to cleaners"""
        notification = {
            'washroom_id': washroom_id,
            'timestamp': datetime.now().isoformat(),
            'type': 'HYGIENE_ALERT',
            'score': score,
            'message': f'Hygiene score dropped to {score}%. Immediate cleaning required.',
            'anomalies': anomalies
        }
        
        # Store in Firebase for Flutter app to pick up
        realtime_db.child(f'notifications/{washroom_id}').push(notification)
        
        print(f"🔔 ALERT SENT: Washroom {washroom_id} - Score: {score}%")
    
    def daily_csv_logger(self):
        """Generate daily CSV logs"""
        while self.running:
            try:
                # Wait until midnight
                now = datetime.now()
                tomorrow = now + timedelta(days=1)
                midnight = datetime(tomorrow.year, tomorrow.month, tomorrow.day)
                sleep_seconds = (midnight - now).total_seconds()
                
                print(f"📅 Next CSV log generation in {sleep_seconds/3600:.1f} hours")
                time.sleep(sleep_seconds)
                
                # Generate yesterday's log
                yesterday = now.date() - timedelta(days=1)
                self.generate_csv_log(yesterday)
                
            except Exception as e:
                print(f"✗ CSV logger error: {e}")
                time.sleep(3600)  # Retry in 1 hour
    
    def generate_csv_log(self, date):
        """Generate CSV log for a specific date"""
        print(f"📝 Generating CSV log for {date}")
        
        # Query Firestore for date range
        start = datetime.combine(date, datetime.min.time())
        end = datetime.combine(date, datetime.max.time())
        
        logs = firestore_db.collection('hygiene_logs')\
            .where('timestamp', '>=', start.isoformat())\
            .where('timestamp', '<=', end.isoformat())\
            .order_by('timestamp').stream()
        
        filename = f"{CSV_LOG_DIR}/hygiene_log_{date}.csv"
        
        with open(filename, 'w', newline='') as csvfile:
            fieldnames = ['timestamp', 'washroom_id', 'final_score', 'base_score', 
                         'air_quality', 'floor_moisture', 'humidity', 'temperature',
                         'footfall_count', 'anomalies_count', 'profile']
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            
            count = 0
            for log in logs:
                data = log.to_dict()
                row = {
                    'timestamp': data.get('timestamp'),
                    'washroom_id': data.get('washroom_id'),
                    'final_score': data.get('final_score'),
                    'base_score': data.get('base_score'),
                    'air_quality': data.get('component_scores', {}).get('air_quality'),
                    'floor_moisture': data.get('component_scores', {}).get('floor_moisture'),
                    'humidity': data.get('component_scores', {}).get('humidity'),
                    'temperature': data.get('component_scores', {}).get('temperature'),
                    'footfall_count': data.get('sensor_data', {}).get('footfall_count'),
                    'anomalies_count': len(data.get('anomalies', [])),
                    'profile': data.get('profile')
                }
                writer.writerow(row)
                count += 1
        
        print(f"✓ CSV log generated: {filename} ({count} records)")
    
    def console_dashboard(self):
        """Live console dashboard"""
        while self.running:
            time.sleep(10)
            
            if last_scores:
                print("\n" + "="*70)
                print("📊 LIVE HYGIENE DASHBOARD")
                print("="*70)
                for washroom_id, score in last_scores.items():
                    status = "🟢 GOOD" if score >= 70 else "🟡 FAIR" if score >= 50 else "🔴 POOR"
                    print(f"{washroom_id}: {score}% {status}")
                print("="*70 + "\n")
    
    def run(self):
        """Start the backend processor"""
        print("🚀 Starting Hygiene Score Backend Engine...")
        print(f"📡 Connecting to MQTT broker: {MQTT_BROKER}")
        
        self.mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
        self.mqtt_client.loop_forever()

# Main execution
if __name__ == "__main__":
    processor = BackendProcessor()
    processor.run()
