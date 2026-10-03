import CoreLocation
import Combine
import Foundation

final class LocSimManager {
    private enum SimulationBehavior {
        // locsim's GPX scenario builder uses 2 for timestamp-driven track delivery.
        static let timestampedTrack: UInt8 = 2
        // The private API's documented values in locsim use 1 for "last location/entry".
        static let holdLastEntry: UInt8 = 1
    }

    private static let simulationManager = CLSimulationManager()
    private static let operationLock = NSLock()
    private static let activeRouteSessionKey = "LocSim.ActiveRouteSession.v3"
    private static let legacyActiveRouteSessionKeys = [
        "LocSim.ActiveRouteSession.v1",
        "LocSim.ActiveRouteSession.v2"
    ]

    static var activeRouteSession: ActiveRouteSession? {
        operationLock.lock()
        defer { operationLock.unlock() }
        return loadActiveRouteSession()
    }

    static func start(at coordinate: SimulatedCoordinate) {
        let location = CLLocation(
            coordinate: coordinate.coreLocationCoordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )

        operationLock.lock()
        defer { operationLock.unlock() }

        simulationManager.stopLocationSimulation()
        simulationManager.clearSimulatedLocations()
        simulationManager.appendSimulatedLocation(location)
        simulationManager.flush()
        simulationManager.startLocationSimulation()
        clearPersistedRouteSessions()
        notifyAutomaticTimeZoneUpdate()
    }

    /// Sends the complete timestamped route to locationd in one operation. Playback therefore
    /// does not depend on an app Timer and can continue while the app is suspended or terminated.
    @discardableResult
    static func start(route: RouteSimulationPlan) throws -> ActiveRouteSession {
        // The private scenario player uses the deltas between CLLocation timestamps. Session
        // progress is anchored later, immediately before playback, so queue preparation time is
        // not incorrectly counted as movement time.
        let locations = try route.makeSimulationLocations(startingAt: Date())
        guard locations.count >= 2 else {
            throw RouteSimulationError.insufficientSamples
        }

        operationLock.lock()
        defer { operationLock.unlock() }

        simulationManager.stopLocationSimulation()
        simulationManager.clearSimulatedLocations()
        clearPersistedRouteSessions()

        // Delivery 2 matches locsim's generated GPX scenarios. Repeat 1 is its documented
        // "last location/entry" mode, so arrival does not loop back to the beginning.
        simulationManager.locationDeliveryBehavior = SimulationBehavior.timestampedTrack
        simulationManager.locationRepeatBehavior = SimulationBehavior.holdLastEntry
        for location in locations {
            simulationManager.appendSimulatedLocation(location)
        }
        simulationManager.flush()

        let session = ActiveRouteSession(
            route: route,
            simulationLocations: locations,
            startedAt: Date()
        )
        guard let sessionData = try? JSONEncoder().encode(session) else {
            simulationManager.clearSimulatedLocations()
            simulationManager.flush()
            throw RouteSimulationError.sessionPersistenceFailed
        }

        simulationManager.startLocationSimulation()

        UserDefaults.standard.set(sessionData, forKey: activeRouteSessionKey)
        notifyAutomaticTimeZoneUpdate()
        return session
    }

    static func stop() {
        operationLock.lock()
        defer { operationLock.unlock() }

        simulationManager.stopLocationSimulation()
        simulationManager.clearSimulatedLocations()
        simulationManager.flush()
        clearPersistedRouteSessions()
        notifyAutomaticTimeZoneUpdate()
    }

    static func stopRoute() {
        stop()
    }

    /// Stops all simulated locations so Core Location resumes reporting the device's real fix.
    static func restoreRealLocation() {
        stop()
    }

    private static func loadActiveRouteSession() -> ActiveRouteSession? {
        guard let data = UserDefaults.standard.data(forKey: activeRouteSessionKey) else {
            return nil
        }
        guard let session = try? JSONDecoder().decode(ActiveRouteSession.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: activeRouteSessionKey)
            return nil
        }
        return session
    }

    private static func clearPersistedRouteSessions() {
        UserDefaults.standard.removeObject(forKey: activeRouteSessionKey)
        for key in legacyActiveRouteSessionKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
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

struct SimulatedCoordinate: Codable, Equatable, Hashable {
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

struct ActiveRouteSession: Codable, Equatable, Identifiable {
    let id: UUID
    let routeName: String
    let startName: String
    let destinationName: String
    let startDisplayCoordinate: SimulatedCoordinate
    let destinationDisplayCoordinate: SimulatedCoordinate
    let routeDisplayCoordinates: [SimulatedCoordinate]
    let startWGS84Coordinate: SimulatedCoordinate
    let destinationWGS84Coordinate: SimulatedCoordinate
    let terminalSpeed: CLLocationSpeed
    let transportMode: RouteTransportMode
    let startedAt: Date
    let expectedArrivalAt: Date
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
    let sampledLocationCount: Int

    fileprivate init(
        route: RouteSimulationPlan,
        simulationLocations: [CLLocation],
        startedAt: Date
    ) {
        let fallbackStartWGS84 = CoordTransform.gcj02ToWgs84(
            route.simulationStartDisplayCoordinate
        )
        let fallbackDestinationWGS84 = CoordTransform.gcj02ToWgs84(
            route.simulationDestinationDisplayCoordinate
        )

        self.id = UUID()
        self.routeName = route.name
        self.startName = route.start.name
        self.destinationName = route.destination.name
        self.startDisplayCoordinate = SimulatedCoordinate(
            route.simulationStartDisplayCoordinate
        )
        self.destinationDisplayCoordinate = SimulatedCoordinate(
            route.simulationDestinationDisplayCoordinate
        )
        self.routeDisplayCoordinates = Self.downsampledDisplayCoordinates(
            route.displayCoordinates
        ).map(SimulatedCoordinate.init)
        self.startWGS84Coordinate = SimulatedCoordinate(
            simulationLocations.first?.coordinate ?? fallbackStartWGS84
        )
        self.destinationWGS84Coordinate = SimulatedCoordinate(
            simulationLocations.last?.coordinate ?? fallbackDestinationWGS84
        )
        self.terminalSpeed = simulationLocations.last?.speed ?? 0
        self.transportMode = route.transportMode
        self.startedAt = startedAt
        self.expectedArrivalAt = startedAt.addingTimeInterval(route.expectedTravelTime)
        self.distance = route.distance
        self.expectedTravelTime = route.expectedTravelTime
        self.sampledLocationCount = route.sampledLocationCount
    }

    /// A few hundred points are enough to redraw a route accurately while keeping the
    /// persisted session compact enough for UserDefaults.
    private static func downsampledDisplayCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        maximumCount: Int = 600
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maximumCount, maximumCount >= 2 else {
            return coordinates
        }

        let lastIndex = coordinates.count - 1
        return (0..<maximumCount).map { outputIndex in
            let progress = Double(outputIndex) / Double(maximumCount - 1)
            let sourceIndex = Int((Double(lastIndex) * progress).rounded())
            return coordinates[min(lastIndex, sourceIndex)]
        }
    }

    var estimatedProgress: Double {
        progress(at: Date())
    }

    var isEstimatedComplete: Bool {
        Date() >= expectedArrivalAt
    }

    func progress(at date: Date) -> Double {
        guard expectedTravelTime > 0 else { return 1 }
        let elapsed = date.timeIntervalSince(startedAt)
        return min(1, max(0, elapsed / expectedTravelTime))
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
