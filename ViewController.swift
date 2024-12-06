import UIKit
import CoreLocation
import MapKit

class ViewController: UIViewController {
    var mapView: MKMapView!
    var trackingButton: UIButton!
    var statusLabel: UILabel!
    var directionScrollView: UIScrollView!
    var directionLabel: UILabel!
    
    let locationManager = CLLocationManager()
    let deadReckoning = DeadReckoning()
    let dataStorage = DataStorage()
    private var trackingPath: [CLLocationCoordinate2D] = []
    private var pathPolyline: MKPolyline?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupLocationManager()
        setupPowerModeObserver()
        mapView.delegate = self
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundState),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    private func setupPowerModeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePowerModeChange),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }
    
    func setupUI() {
        view.backgroundColor = .white
        
        mapView = MKMapView()
        mapView.layer.cornerRadius = 15
        view.addSubview(mapView)
        
        statusLabel = UILabel()
        statusLabel.text = "Press Start to begin tracking."
        statusLabel.textColor = .darkGray
        statusLabel.font = UIFont.systemFont(ofSize: 16)
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)
        
        directionScrollView = UIScrollView()
        view.addSubview(directionScrollView)
        
        directionLabel = UILabel()
        directionLabel.text = "Direction History:\n"
        directionLabel.textColor = .darkGray
        directionLabel.font = UIFont.systemFont(ofSize: 16)
        directionLabel.numberOfLines = 0
        directionScrollView.addSubview(directionLabel)
        
        trackingButton = UIButton(type: .system)
        trackingButton.setTitle("Start Tracking", for: .normal)
        trackingButton.setTitleColor(.white, for: .normal)
        trackingButton.backgroundColor = UIColor.systemBlue
        trackingButton.layer.cornerRadius = 10
        trackingButton.addTarget(self, action: #selector(toggleTracking), for: .touchUpInside)
        view.addSubview(trackingButton)
        
        setConstraints()
    }
    
    func setConstraints() {
        mapView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        directionScrollView.translatesAutoresizingMaskIntoConstraints = false
        directionLabel.translatesAutoresizingMaskIntoConstraints = false
        trackingButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            mapView.heightAnchor.constraint(equalToConstant: 300),
            
            statusLabel.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            directionScrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            directionScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            directionScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            directionScrollView.bottomAnchor.constraint(equalTo: trackingButton.topAnchor, constant: -20),
            
            directionLabel.topAnchor.constraint(equalTo: directionScrollView.topAnchor),
            directionLabel.leadingAnchor.constraint(equalTo: directionScrollView.leadingAnchor),
            directionLabel.trailingAnchor.constraint(equalTo: directionScrollView.trailingAnchor),
            directionLabel.bottomAnchor.constraint(equalTo: directionScrollView.bottomAnchor),
            directionLabel.widthAnchor.constraint(equalTo: directionScrollView.widthAnchor),
            
            trackingButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            trackingButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            trackingButton.widthAnchor.constraint(equalToConstant: 200),
            trackingButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    @objc private func handleBackgroundState() {
        print("App entering background")
        deadReckoning.stopDeviceMotionUpdates()
    }
    
    @objc private func handlePowerModeChange() {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
//        deadReckoning.handleLowPowerMode(enabled: isLowPower)
        
        if isLowPower {
            statusLabel.text = "Low Power Mode - Reduced Accuracy"
        }
    }
    
    @objc func toggleTracking() {
        if deadReckoning.isTracking {
            stopTracking()
        } else {
            startTracking()
        }
        deadReckoning.isTracking.toggle()
    }
    
    func startTracking() {
        trackingPath.removeAll()
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        
        trackingButton.setTitle("Stop Tracking", for: .normal)
        trackingButton.backgroundColor = UIColor.systemRed
        statusLabel.text = "Tracking started."
        directionLabel.text = "Direction History:\n"
        
        if let location = locationManager.location {
            dataStorage.storeInitialGPS(location: location)
            deadReckoning.startTracking(location: location)
            MapViewHelper.centerMapOnLocation(mapView: mapView, location: location)
        }
        
        locationManager.stopUpdatingLocation()
        deadReckoning.startDeviceMotionUpdates { [weak self] position, direction, sensorReadings in
            self?.updateUI(position: position, direction: direction, sensorReadings: sensorReadings)
        }
    }
    
    func stopTracking() {
        trackingButton.setTitle("Start Tracking", for: .normal)
        trackingButton.backgroundColor = UIColor.systemBlue
        statusLabel.text = "Tracking stopped."
        
        deadReckoning.stopDeviceMotionUpdates()
        dataStorage.saveToJSONFile()
        
        if trackingPath.count >= 2 {
            let region = MKCoordinateRegion(
                coordinates: trackingPath,
                latitudinalMeters: 200,
                longitudinalMeters: 200
            )
            mapView.setRegion(region, animated: true)
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        deadReckoning.stopDeviceMotionUpdates()
    }
    
    func updateUI(position: CLLocationCoordinate2D, direction: String, sensorReadings: [String: Double]) {
        trackingPath.append(position)
        
        if let existingPolyline = pathPolyline {
            mapView.removeOverlay(existingPolyline)
        }
        
        if trackingPath.count >= 2 {
            pathPolyline = MKPolyline(coordinates: trackingPath, count: trackingPath.count)
            if let polyline = pathPolyline {
                mapView.addOverlay(polyline)
            }
        }
        
        if mapView.annotations.isEmpty {
            let startingAnnotation = MKPointAnnotation()
            startingAnnotation.coordinate = position
            startingAnnotation.title = "Starting Point"
            mapView.addAnnotation(startingAnnotation)
        } else {
            if let lastAnnotation = mapView.annotations.last, lastAnnotation.title != "Starting Point" {
                mapView.removeAnnotation(lastAnnotation)
            }
            let currentAnnotation = MKPointAnnotation()
            currentAnnotation.coordinate = position
            currentAnnotation.title = "Current Position"
            mapView.addAnnotation(currentAnnotation)
        }
        
        let region = MKCoordinateRegion(
            center: position,
            latitudinalMeters: 100,
            longitudinalMeters: 100
        )
        mapView.setRegion(region, animated: true)
        
        let newText = "• \(direction) at (\(String(format: "%.6f", position.latitude)), \(String(format: "%.6f", position.longitude)))\n"
        directionLabel.text! += newText
        
        let bottom = CGPoint(x: 0, y: directionScrollView.contentSize.height - directionScrollView.bounds.height)
        directionScrollView.setContentOffset(bottom, animated: true)
        
        dataStorage.addSensorData(position: position, direction: direction, sensorReadings: sensorReadings)
    }
}

extension ViewController: CLLocationManagerDelegate {}

extension MKCoordinateRegion {
    init(coordinates: [CLLocationCoordinate2D], latitudinalMeters: CLLocationDistance, longitudinalMeters: CLLocationDistance) {
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        
        coordinates.forEach { coordinate in
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        self.init(
            center: center,
            latitudinalMeters: latitudinalMeters,
            longitudinalMeters: longitudinalMeters
        )
    }
}

extension ViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .blue
            renderer.lineWidth = 4.0
            renderer.alpha = 0.8
            return renderer
        }
        return MKOverlayRenderer()
    }
}

