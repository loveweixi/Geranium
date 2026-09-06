import CoreLocation
import Combine
import Foundation

final class LocSimManager {
    private static let simulationManager = CLSimulationManager()

    static func start(at coordinate: SimulatedCoordinate) {
        let location = CLLocation(
            coordinate: coordinate.coreLocationCoordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )

        simulationManager.stopLocationSimulation()
        simulationManager.clearSimulatedLocations()
        simulationManager.appendSimulatedLocation(location)
        simulationManager.flush()
        simulationManager.startLocationSimulation()
        notifyAutomaticTimeZoneUpdate()
    }

    static func stop() {
        simulationManager.stopLocationSimulation()
        simulationManager.clearSimulatedLocations()
        simulationManager.flush()
        notifyAutomaticTimeZoneUpdate()
    }

    private static func notifyAutomaticTimeZoneUpdate() {
        CFNotificationCenterPostNotificationWithOptions(
            CFNotificationCenterGetDarwinNotifyCenter(),
            .init("AutomaticTimeZoneUpdateNeeded" as CFString),
            nil,
            nil,
            kCFNotificationDeliverImmediately
        )
    }
}

struct SimulatedCoordinate: Equatable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coreLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class LocationAuthorizationModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
    }
}
