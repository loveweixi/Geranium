import CoreLocation
import Foundation
import MapKit

enum RouteTransportMode: String, Codable, CaseIterable, Identifiable {
    case driving
    case walking

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .driving:
            return "驾车"
        case .walking:
            return "步行"
        }
    }

    fileprivate var mapKitTransportType: MKDirectionsTransportType {
        switch self {
        case .driving:
            return .automobile
        case .walking:
            return .walking
        }
    }

    fileprivate var fallbackSpeed: CLLocationSpeed {
        switch self {
        case .driving:
            return 13.9
        case .walking:
            return 1.35
        }
    }
}

struct RouteWaypoint: Equatable {
    let name: String
    let coordinate: CLLocationCoordinate2D

    init(name: String, coordinate: CLLocationCoordinate2D) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.coordinate = coordinate
    }

    static func == (lhs: RouteWaypoint, rhs: RouteWaypoint) -> Bool {
        lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// A calculated MapKit route plus a compact, in-memory representation of its sampled path.
/// The sampled coordinates are intentionally not Codable so a full route cannot accidentally
/// be written to UserDefaults. Only ActiveRouteSession metadata is persisted.
struct RouteSimulationPlan: Identifiable {
    let id: UUID
    let name: String
    let start: RouteWaypoint
    let destination: RouteWaypoint
    let transportMode: RouteTransportMode
    let polyline: MKPolyline
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval

    private let sampledDisplayCoordinates: [CLLocationCoordinate2D]

    var sampledLocationCount: Int { sampledDisplayCoordinates.count }
    var simulationStartDisplayCoordinate: CLLocationCoordinate2D {
        sampledDisplayCoordinates.first ?? start.coordinate
    }
    var simulationDestinationDisplayCoordinate: CLLocationCoordinate2D {
        sampledDisplayCoordinates.last ?? destination.coordinate
    }

    /// Original MapKit route vertices for drawing the route without rendering every playback sample.
    var displayCoordinates: [CLLocationCoordinate2D] {
        guard polyline.pointCount > 0 else { return [] }
        var coordinates = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(
            &coordinates,
            range: NSRange(location: 0, length: polyline.pointCount)
        )
        return coordinates
    }

    fileprivate init(
        route: MKRoute,
        start: RouteWaypoint,
        destination: RouteWaypoint,
        transportMode: RouteTransportMode
    ) throws {
        let polylineDistance = RoutePathSampler.length(of: route.polyline)
        let usableDistance = route.distance > 0 ? route.distance : polylineDistance
        guard usableDistance.isFinite,
            polylineDistance.isFinite,
            usableDistance > 0,
            polylineDistance > 0
        else {
            throw RouteSimulationError.routeTooShort
        }

        let fallbackDuration = usableDistance / transportMode.fallbackSpeed
        let usableTravelTime = route.expectedTravelTime > 0
            ? route.expectedTravelTime
            : fallbackDuration

        guard usableTravelTime.isFinite, usableTravelTime > 0 else {
            throw RouteSimulationError.invalidTravelTime
        }

        self.id = UUID()
        self.name = route.name.isEmpty
            ? "\(start.name.isEmpty ? "起点" : start.name) → \(destination.name.isEmpty ? "终点" : destination.name)"
            : route.name
        self.start = start
        self.destination = destination
        self.transportMode = transportMode
        self.polyline = route.polyline
        self.distance = usableDistance
        self.expectedTravelTime = max(1, usableTravelTime)
        self.sampledDisplayCoordinates = try RoutePathSampler.sample(
            polyline: route.polyline,
            travelTime: max(1, usableTravelTime)
        )
    }

    /// Produces timestamped WGS-84 locations immediately before playback begins.
    /// MapKit coordinates shown in mainland China are converted from GCJ-02 first.
    func makeSimulationLocations(startingAt startDate: Date = Date()) throws -> [CLLocation] {
        guard sampledDisplayCoordinates.count >= 2 else {
            throw RouteSimulationError.insufficientSamples
        }

        let wgsCoordinates = sampledDisplayCoordinates.map(CoordTransform.gcj02ToWgs84)
        let interval = expectedTravelTime / Double(wgsCoordinates.count - 1)
        guard interval.isFinite, interval > 0 else {
            throw RouteSimulationError.invalidTravelTime
        }

        var locations: [CLLocation] = []
        locations.reserveCapacity(wgsCoordinates.count)

        var lastCourse: CLLocationDirection = 0

        for index in wgsCoordinates.indices {
            let coordinate = wgsCoordinates[index]
            let timestamp = startDate.addingTimeInterval(Double(index) * interval)

            let course: CLLocationDirection
            let speed: CLLocationSpeed
            if index < wgsCoordinates.count - 1 {
                let nextCoordinate = wgsCoordinates[index + 1]
                let currentLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let nextLocation = CLLocation(latitude: nextCoordinate.latitude, longitude: nextCoordinate.longitude)
                speed = max(0, nextLocation.distance(from: currentLocation) / interval)
                course = RoutePathSampler.bearing(from: coordinate, to: nextCoordinate)
                lastCourse = course
            } else {
                course = lastCourse
                // Repeat behavior 1 keeps publishing this final entry after arrival. Its speed
                // must be zero or clients would report motion while the coordinate is stationary.
                speed = 0
            }

            locations.append(
                CLLocation(
                    coordinate: coordinate,
                    altitude: 0,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    course: course,
                    speed: speed,
                    timestamp: timestamp
                )
            )
        }

        return locations
    }
}

enum RouteSimulationPlanner {
    /// Calculates the recommended route. Retain the returned MKDirections when cancellation is
    /// needed; the completion also captures it until the request has finished.
    @discardableResult
    static func calculateRoute(
        from start: RouteWaypoint,
        to destination: RouteWaypoint,
        mode: RouteTransportMode,
        completion: @escaping (Result<RouteSimulationPlan, RouteSimulationError>) -> Void
    ) -> MKDirections? {
        guard CLLocationCoordinate2DIsValid(start.coordinate) else {
            completion(.failure(.invalidStartCoordinate))
            return nil
        }
        guard CLLocationCoordinate2DIsValid(destination.coordinate) else {
            completion(.failure(.invalidDestinationCoordinate))
            return nil
        }

        let request = MKDirections.Request()
        request.source = mapItem(for: start)
        request.destination = mapItem(for: destination)
        request.transportType = mode.mapKitTransportType
        request.requestsAlternateRoutes = false
        request.departureDate = Date()

        let directions = MKDirections(request: request)
        directions.calculate { [directions] response, error in
            _ = directions
            if let error = error {
                completion(.failure(.routeCalculationFailed(error.localizedDescription)))
                return
            }

            guard let route = response?.routes.first else {
                completion(.failure(.routeNotFound))
                return
            }

            do {
                let plan = try RouteSimulationPlan(
                    route: route,
                    start: start,
                    destination: destination,
                    transportMode: mode
                )
                completion(.success(plan))
            } catch let routeError as RouteSimulationError {
                completion(.failure(routeError))
            } catch {
                completion(.failure(.routeCalculationFailed(error.localizedDescription)))
            }
        }

        return directions
    }

    private static func mapItem(for waypoint: RouteWaypoint) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: waypoint.coordinate))
        if !waypoint.name.isEmpty {
            item.name = waypoint.name
        }
        return item
    }
}

enum RouteSimulationError: LocalizedError, Equatable {
    case invalidStartCoordinate
    case invalidDestinationCoordinate
    case routeNotFound
    case routeTooShort
    case invalidTravelTime
    case insufficientSamples
    case routeCalculationFailed(String)
    case sessionPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidStartCoordinate:
            return "起点坐标无效。"
        case .invalidDestinationCoordinate:
            return "终点坐标无效。"
        case .routeNotFound:
            return "没有找到可用路线，请调整起点、终点或出行方式。"
        case .routeTooShort:
            return "路线距离太短，无法生成连续轨迹。"
        case .invalidTravelTime:
            return "路线预计时间无效。"
        case .insufficientSamples:
            return "路线采样点不足，无法开始模拟。"
        case .routeCalculationFailed(let message):
            return "路线计算失败：\(message)"
        case .sessionPersistenceFailed:
            return "无法保存本次轨迹模拟状态。"
        }
    }
}

private enum RoutePathSampler {
    /// Keep normal routes close to a two-second cadence, while limiting exceptionally long
    /// journeys to a safe queue size for locationd.
    private static let preferredInterval: TimeInterval = 2
    private static let maximumLocationCount = 3_600

    static func length(of polyline: MKPolyline) -> CLLocationDistance {
        guard polyline.pointCount >= 2 else { return 0 }
        let points = polyline.points()
        var total: CLLocationDistance = 0
        for index in 1..<polyline.pointCount {
            total += points[index - 1].distance(to: points[index])
        }
        return total
    }

    static func sample(
        polyline: MKPolyline,
        travelTime: TimeInterval
    ) throws -> [CLLocationCoordinate2D] {
        guard polyline.pointCount >= 2 else {
            throw RouteSimulationError.routeTooShort
        }

        let sourcePoints = polyline.points()
        var cumulativeDistances = [CLLocationDistance](repeating: 0, count: polyline.pointCount)
        for index in 1..<polyline.pointCount {
            cumulativeDistances[index] = cumulativeDistances[index - 1]
                + sourcePoints[index - 1].distance(to: sourcePoints[index])
        }

        guard let totalDistance = cumulativeDistances.last, totalDistance > 0 else {
            throw RouteSimulationError.routeTooShort
        }

        let uncappedStepCount = max(1, Int(ceil(travelTime / preferredInterval)))
        let stepCount = min(uncappedStepCount, maximumLocationCount - 1)

        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(stepCount + 1)
        var segmentIndex = 1

        for step in 0...stepCount {
            let progress = Double(step) / Double(stepCount)
            let targetDistance = totalDistance * progress

            while segmentIndex < cumulativeDistances.count - 1
                && cumulativeDistances[segmentIndex] < targetDistance
            {
                segmentIndex += 1
            }

            let previousIndex = max(0, segmentIndex - 1)
            let segmentStartDistance = cumulativeDistances[previousIndex]
            let segmentEndDistance = cumulativeDistances[segmentIndex]
            let segmentDistance = segmentEndDistance - segmentStartDistance
            let fraction = segmentDistance > 0
                ? (targetDistance - segmentStartDistance) / segmentDistance
                : 0

            let first = sourcePoints[previousIndex]
            let second = sourcePoints[segmentIndex]
            let interpolated = MKMapPoint(
                x: first.x + (second.x - first.x) * fraction,
                y: first.y + (second.y - first.y) * fraction
            )
            result.append(interpolated.coordinate)
        }

        return result
    }

    static func bearing(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let startLatitude = start.latitude * .pi / 180
        let destinationLatitude = destination.latitude * .pi / 180
        let longitudeDelta = (destination.longitude - start.longitude) * .pi / 180

        let y = sin(longitudeDelta) * cos(destinationLatitude)
        let x = cos(startLatitude) * sin(destinationLatitude)
            - sin(startLatitude) * cos(destinationLatitude) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
