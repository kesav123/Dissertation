import CoreLocation

class KalmanFilter {
    private var state: CLLocationCoordinate2D? = nil
    private var uncertainty: Double = 1.0
    private let processNoise: Double = 0.01
    private let measurementNoise: Double = 0.1

    func reset(to position: CLLocationCoordinate2D) {
        state = position
        uncertainty = 1.0
    }

    func update(rawPosition: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard let state = state else {
            self.state = rawPosition
            return rawPosition
        }

        // Prediction step
        let predictedState = state
        let predictedUncertainty = uncertainty + processNoise

        // Measurement update step
        let kalmanGain = predictedUncertainty / (predictedUncertainty + measurementNoise)
        let updatedLatitude = predictedState.latitude + kalmanGain * (rawPosition.latitude - predictedState.latitude)
        let updatedLongitude = predictedState.longitude + kalmanGain * (rawPosition.longitude - predictedState.longitude)

        // Update state and uncertainty
        self.state = CLLocationCoordinate2D(latitude: updatedLatitude, longitude: updatedLongitude)
        self.uncertainty = (1 - kalmanGain) * predictedUncertainty

        return self.state!
    }
}
