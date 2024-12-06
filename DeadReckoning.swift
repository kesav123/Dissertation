











import CoreMotion
import CoreLocation

class MovingAverageFilter {
    private let windowSize: Int
    private var samples: [Double] = []
    
    init(windowSize: Int) {
        self.windowSize = windowSize
    }
    
    func addSample(_ sample: Double) -> Double {
        samples.append(sample)
        if samples.count > windowSize {
            samples.removeFirst()
        }
        return samples.reduce(0, +) / Double(samples.count)
    }
    
    func reset() {
        samples.removeAll()
    }
}

class SensorFilter {
    private var lastAcceleration: (x: Double, y: Double, z: Double) = (0, 0, 0)
    private let alpha = 0.1

    func filterAcceleration(x: Double, y: Double, z: Double) -> (x: Double, y: Double, z: Double) {
        lastAcceleration.x = (alpha * x) + ((1.0 - alpha) * lastAcceleration.x)
        lastAcceleration.y = (alpha * y) + ((1.0 - alpha) * lastAcceleration.y)
        lastAcceleration.z = (alpha * z) + ((1.0 - alpha) * lastAcceleration.z)
        return lastAcceleration
    }
    
    func reset() {
        lastAcceleration = (0, 0, 0)
    }
}

class DeadReckoning: NSObject, CLLocationManagerDelegate {
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private let sensorFilter = SensorFilter()
    private let headingFilter = MovingAverageFilter(windowSize: 5)
    private var isLowPowerMode: Bool = false
    
    private let normalUpdateInterval: TimeInterval = 0.1
    private let lowPowerUpdateInterval: TimeInterval = 0.5
    
    private var initialHeading: Double?
    var isTracking = false
    private var positionEstimate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    private var currentHeading: Double = 0.0
    private var stepCount: Int = 0
    
    private let motionUpdateInterval: TimeInterval = 0.2
    private let headingUpdateInterval: TimeInterval = 1.0
    
    // Tuned parameters
    private let stepDistance = 0.65
    private let minimumMovementThreshold = 0.1
    private let stepDetectionThreshold = 0.15
    private let headingChangeThreshold = 2.0
    private let updateInterval: TimeInterval = 0.1
    
    private var lastStepTimestamp: TimeInterval = 0
    private var lastPosition: CLLocationCoordinate2D?
    private var kalmanFilter = KalmanFilter()
    
    override init() {
        super.init()
        setupLocationManager()
        setupMotionManager()
    }
    
    func handleLowPowerMode() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            isLowPowerMode = true
            motionManager.deviceMotionUpdateInterval = 0.5
            locationManager.headingFilter = 10
        }
    }
    
    func handleLowPowerMode(enabled: Bool) {
        isLowPowerMode = enabled
        updateSensorIntervals()
        print("Power mode changed - Low Power: \(enabled)")
    }
    
    private func updateSensorIntervals() {
        let interval = isLowPowerMode ? lowPowerUpdateInterval : normalUpdateInterval
        motionManager.deviceMotionUpdateInterval = interval
        locationManager.headingFilter = isLowPowerMode ? 10 : 1
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.headingFilter = 5
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.startUpdatingHeading()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading = newHeading.trueHeading
        print("Compass Heading: \(trueHeading)°")
        
        if newHeading.headingAccuracy > 0 {
            currentHeading = trueHeading
        }
    }
    
    private func setupMotionManager() {
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.deviceMotionUpdateInterval = motionUpdateInterval
        motionManager.magnetometerUpdateInterval = headingUpdateInterval
        print("Motion manager setup complete")
    }
    
    func startTracking(location: CLLocation) {
        print("Starting tracking from: \(location.coordinate)")
        positionEstimate = location.coordinate
        lastPosition = location.coordinate
        kalmanFilter.reset(to: positionEstimate)
        sensorFilter.reset()
        headingFilter.reset()
        stepCount = 0
        initialHeading = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.initialHeading = self.currentHeading
            print("Initial heading set to: \(self.currentHeading)°")
        }
    }
    
    func startDeviceMotionUpdates(updateHandler: @escaping (CLLocationCoordinate2D, String, [String: Double]) -> Void) {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion unavailable")
            return
        }
        
        print("Starting motion updates...")
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else {
                if let error = error {
                    print("Motion error: \(error)")
                }
                return
            }
            
            self.processDeviceMotion(motion, updateHandler: updateHandler)
        }
    }
    
    private func processDeviceMotion(_ deviceMotion: CMDeviceMotion, updateHandler: @escaping (CLLocationCoordinate2D, String, [String: Double]) -> Void) {
        let currentTime = Date().timeIntervalSince1970
        
        if let heading = locationManager.heading?.trueHeading {
            currentHeading = headingFilter.addSample(heading)
            print("Current Heading: \(currentHeading)°")
        }
        
        let attitude = deviceMotion.attitude
        var trueHeading = attitude.yaw * 180 / .pi
        trueHeading = (trueHeading + 360).truncatingRemainder(dividingBy: 360)
        currentHeading = headingFilter.addSample(trueHeading)
        
        let userAcc = deviceMotion.userAcceleration
        let magnitude = sqrt(pow(userAcc.x, 2) + pow(userAcc.y, 2) + pow(userAcc.z, 2))
        
        print("Heading: \(currentHeading)°, Magnitude: \(magnitude)")
        
        if magnitude > stepDetectionThreshold && (currentTime - lastStepTimestamp) > 0.3 {
            lastStepTimestamp = currentTime
            stepCount += 1
            updatePosition(heading: currentHeading, timestamp: currentTime, updateHandler: updateHandler)
        }
    }
    
    private func updatePosition(heading: Double, timestamp: TimeInterval, updateHandler: (CLLocationCoordinate2D, String, [String: Double]) -> Void) {
        let headingRadians = heading * .pi / 180
        let direction = determineDirection(heading: headingRadians)
        
        let earthRadius = 6371000.0
        let deltaLat = (stepDistance * cos(headingRadians)) / earthRadius
        let deltaLon = (stepDistance * sin(headingRadians)) / (earthRadius * cos(positionEstimate.latitude * .pi / 180))
        
        var newPosition = positionEstimate
        newPosition.latitude += deltaLat * (180 / .pi)
        newPosition.longitude += deltaLon * (180 / .pi)
        
        positionEstimate = kalmanFilter.update(rawPosition: newPosition)
        
        let sensorReadings: [String: Double] = [
            "heading": heading,
            "stepCount": Double(stepCount)
        ]
        
        updateHandler(positionEstimate, direction, sensorReadings)
    }
    
    private func determineDirection(heading: Double) -> String {
        let angle = heading * 180 / .pi
        switch angle {
        case -22.5..<22.5: return "North"
        case 22.5..<67.5: return "Northeast"
        case 67.5..<112.5: return "East"
        case 112.5..<157.5: return "Southeast"
        case 157.5..<180, -180..<(-157.5): return "South"
        case -157.5..<(-112.5): return "Southwest"
        case -112.5..<(-67.5): return "West"
        case -67.5..<(-22.5): return "Northwest"
        default: return "North"
        }
    }
    
    func stopDeviceMotionUpdates() {
        print("Stopping motion updates")
        motionManager.stopDeviceMotionUpdates()
        locationManager.stopUpdatingHeading()
        sensorFilter.reset()
        headingFilter.reset()
    }
}
