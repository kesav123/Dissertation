import CoreLocation

class DataStorage {
    private var initialGPSData: [String: Any] = [:]
    private var sensorData: [[String: Any]] = []
    
    // Add timestamp to track when data was collected
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    func storeInitialGPS(location: CLLocation) {
        initialGPSData = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "timestamp": dateFormatter.string(from: Date())
        ]
        print("Initial GPS stored: \(initialGPSData)")
    }
    
    func addSensorData(position: CLLocationCoordinate2D, direction: String, sensorReadings: [String: Double]) {
        var dataPoint: [String: Any] = [
            "latitude": position.latitude,
            "longitude": position.longitude,
            "direction": direction,
            "timestamp": dateFormatter.string(from: Date())
        ]
        
        // Map sensor readings with correct keys
        let sensorKeys = [
            "accelerationX", "accelerationY", "accelerationZ",
            "gyroX", "gyroY", "gyroZ",
            "heading", "magneticAccuracy"
        ]
        
        for key in sensorKeys {
            dataPoint[key] = sensorReadings[key] ?? 0.0
        }
        
        sensorData.append(dataPoint)
    }
    
    func saveToJSONFile() {
        let json: [String: Any] = [
            "initialGPS": initialGPSData,
            "sensorData": sensorData,
            "recordingEnd": dateFormatter.string(from: Date())
        ]
        
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Error: Cannot access document directory")
            return
        }
        
        let filePath = documentDirectory.appendingPathComponent("trackingData.json")
        
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            try data.write(to: filePath)
            print("Data saved successfully to: \(filePath)")
            print("Total data points: \(sensorData.count)")
        } catch {
            print("Error saving JSON file: \(error.localizedDescription)")
        }
    }
    
    func loadFromJSONFile() -> [String: Any]? {
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Error: Cannot access document directory")
            return nil
        }
        
        let filePath = documentDirectory.appendingPathComponent("trackingData.json")
        
        do {
            let data = try Data(contentsOf: filePath)
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            print("Data loaded successfully")
            return json
        } catch {
            print("Error loading JSON file: \(error.localizedDescription)")
            return nil
        }
    }
}

