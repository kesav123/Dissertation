import MapKit

class MapViewHelper {
    /// Centers the map on the given location and adds a "Starting Point" annotation
    static func centerMapOnLocation(mapView: MKMapView, location: CLLocation) {
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        mapView.setRegion(region, animated: true)

        // Clear existing annotations to avoid duplicates
        mapView.removeAnnotations(mapView.annotations)

        // Add the starting point annotation
        let annotation = MKPointAnnotation()
        annotation.coordinate = location.coordinate
        annotation.title = "Starting Point"
        mapView.addAnnotation(annotation)
    }

    /// Draws a path on the map based on the provided coordinates
    static func drawPath(mapView: MKMapView, path: [CLLocationCoordinate2D]) {
        // Clear existing overlays before drawing the new path
        mapView.removeOverlays(mapView.overlays)

        // Create and add a polyline overlay for the path
        guard path.count > 1 else {
            print("Path has insufficient points to draw a line.")
            return
        }

        let polyline = MKPolyline(coordinates: path, count: path.count)
        mapView.addOverlay(polyline)
    }

    /// Returns a renderer for the given map overlay (polyline)
    static func getRenderer(for overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineWidth = 3
            renderer.strokeColor = UIColor.blue.withAlphaComponent(0.7) // Add transparency for better visibility
            renderer.lineDashPattern = [4, 2] // Optional: Dashed line style
            return renderer
        }
        return MKOverlayRenderer()
    }
}
