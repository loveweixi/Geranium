import MapKit
import SwiftUI

struct MapCameraTarget: Equatable {
    let id = UUID()
    /// A nil coordinate means the map should return to the live system location.
    let coordinate: SimulatedCoordinate?
}

/// A route whose coordinates are already in MapKit's display coordinate system.
/// Create a new id whenever the route geometry changes.
struct MapRouteOverlay {
    let id: UUID
    let displayCoordinates: [CLLocationCoordinate2D]

    init(
        id: UUID = UUID(),
        displayCoordinates: [CLLocationCoordinate2D]
    ) {
        self.id = id
        self.displayCoordinates = displayCoordinates
    }
}

struct CustomMapView: UIViewRepresentable {
    @Binding var selectedCoordinate: SimulatedCoordinate?
    @Binding var selectedName: String?
    @Binding var errorMessage: String?

    let cameraTarget: MapCameraTarget?
    var routeOverlay: MapRouteOverlay? = nil

    func makeUIView(context: Context) -> MKMapView {
        // Match the upstream construction path for iOS 15 compatibility. SwiftUI
        // owns the final frame, but starting with MKMapView's default initializer
        // avoids a zero-sized renderer during the first layout pass on older iPads.
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .standard
        mapView.backgroundColor = .systemBackground
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = false
        mapView.pointOfInterestFilter = .includingAll

        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.8617, longitude: 104.1954),
            span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 36)
        )
        mapView.setRegion(initialRegion, animated: false)

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapRecognizer.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapRecognizer)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        if routeOverlay == nil {
            if let selectedCoordinate,
               (context.coordinator.lastRenderedCoordinate != selectedCoordinate
                || !context.coordinator.isSelectionPinVisible(on: mapView)) {
                context.coordinator.renderPin(
                    for: selectedCoordinate,
                    on: mapView
                )
            } else if selectedCoordinate == nil,
                      context.coordinator.lastRenderedCoordinate != nil {
                context.coordinator.clearSelection(on: mapView)
            }
        }

        if let cameraTarget,
           context.coordinator.lastCameraTargetID != cameraTarget.id {
            context.coordinator.lastCameraTargetID = cameraTarget.id
            if let coordinate = cameraTarget.coordinate {
                context.coordinator.renderPin(for: coordinate, on: mapView)
                context.coordinator.centerMap(
                    on: coordinate,
                    mapView: mapView,
                    animated: true
                )
            } else {
                context.coordinator.followSystemLocation(on: mapView)
            }
        }

        if context.coordinator.lastRouteOverlayID != routeOverlay?.id {
            context.coordinator.renderRoute(routeOverlay, on: mapView)
        }

        // A point selected before entering route mode can coincide with the
        // green start marker. Keep its state, but hide the duplicate pin until
        // the route is dismissed.
        if routeOverlay != nil {
            context.coordinator.hideSelectionPin(on: mapView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CustomMapView
        let selectionPin = MKPointAnnotation()
        let routeStartPin = MKPointAnnotation()
        let routeEndPin = MKPointAnnotation()
        var lastRenderedCoordinate: SimulatedCoordinate?
        var lastCameraTargetID: UUID?
        var lastRouteOverlayID: UUID?

        private var hasCenteredOnUser = false
        private var hasRenderedMap = false
        private var routePolyline: MKPolyline?

        init(parent: CustomMapView) {
            self.parent = parent
            selectionPin.title = "已选位置"
            routeStartPin.title = "起点"
            routeEndPin.title = "终点"
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let mapView = gesture.view as? MKMapView,
                  parent.routeOverlay == nil else { return }

            let point = gesture.location(in: mapView)
            let mapCoordinate = mapView.convert(point, toCoordinateFrom: mapView)
            let wgs84Coordinate = CoordTransform.gcj02ToWgs84(mapCoordinate)
            parent.selectedName = nil
            parent.selectedCoordinate = SimulatedCoordinate(wgs84Coordinate)
        }

        func renderPin(
            for coordinate: SimulatedCoordinate,
            on mapView: MKMapView
        ) {
            if mapView.userTrackingMode != .none {
                mapView.setUserTrackingMode(.none, animated: false)
            }

            selectionPin.coordinate = CoordTransform.wgs84ToGcj02(
                coordinate.coreLocationCoordinate
            )

            if !mapView.annotations.contains(where: { $0 === selectionPin }) {
                mapView.addAnnotation(selectionPin)
            }
            lastRenderedCoordinate = coordinate
        }

        func clearSelection(on mapView: MKMapView) {
            hideSelectionPin(on: mapView)
            lastRenderedCoordinate = nil
        }

        func isSelectionPinVisible(on mapView: MKMapView) -> Bool {
            mapView.annotations.contains { $0 === selectionPin }
        }

        func hideSelectionPin(on mapView: MKMapView) {
            if isSelectionPinVisible(on: mapView) {
                mapView.removeAnnotation(selectionPin)
            }
        }

        func followSystemLocation(on mapView: MKMapView) {
            clearSelection(on: mapView)
            mapView.setUserTrackingMode(.follow, animated: true)
        }

        func renderRoute(
            _ route: MapRouteOverlay?,
            on mapView: MKMapView
        ) {
            clearRoute(on: mapView)
            lastRouteOverlayID = route?.id

            guard let route else { return }

            let coordinates = route.displayCoordinates.filter {
                CLLocationCoordinate2DIsValid($0)
                    && $0.latitude.isFinite
                    && $0.longitude.isFinite
            }
            guard coordinates.count >= 2,
                  let start = coordinates.first,
                  let end = coordinates.last else { return }

            // A previous "restore" action can leave the map following the live
            // user location. Stop tracking before fitting a planned route so
            // later location updates do not immediately pull the camera away.
            if mapView.userTrackingMode != .none {
                mapView.setUserTrackingMode(.none, animated: false)
            }

            routeStartPin.coordinate = start
            routeEndPin.coordinate = end
            mapView.addAnnotations([routeStartPin, routeEndPin])

            let polyline = MKPolyline(
                coordinates: coordinates,
                count: coordinates.count
            )
            routePolyline = polyline
            mapView.addOverlay(polyline, level: .aboveRoads)

            if polyline.boundingMapRect.isNull || polyline.boundingMapRect.isEmpty {
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: start,
                        span: MKCoordinateSpan(
                            latitudeDelta: 0.02,
                            longitudeDelta: 0.02
                        )
                    ),
                    animated: true
                )
            } else {
                // The route controls are overlaid on the bottom of the map and
                // vary in height across iPhone/iPad and orientation. Reserve a
                // proportional inset so both endpoints remain above the panel.
                let mapHeight = mapView.bounds.height > 0
                    ? mapView.bounds.height
                    : UIScreen.main.bounds.height
                let topInset = min(100, max(56, mapHeight * 0.10))
                let desiredBottomInset = min(340, max(160, mapHeight * 0.45))
                let bottomInset = min(
                    desiredBottomInset,
                    max(80, mapHeight - topInset - 100)
                )
                mapView.setVisibleMapRect(
                    polyline.boundingMapRect,
                    edgePadding: UIEdgeInsets(
                        top: topInset,
                        left: 36,
                        bottom: bottomInset,
                        right: 36
                    ),
                    animated: true
                )
            }
        }

        private func clearRoute(on mapView: MKMapView) {
            if let routePolyline {
                mapView.removeOverlay(routePolyline)
            }
            routePolyline = nil

            let routeAnnotations: [MKAnnotation] = [routeStartPin, routeEndPin]
                .filter { routeAnnotation in
                    mapView.annotations.contains { $0 === routeAnnotation }
                }
            if !routeAnnotations.isEmpty {
                mapView.removeAnnotations(routeAnnotations)
            }
        }

        func centerMap(
            on coordinate: SimulatedCoordinate,
            mapView: MKMapView,
            animated: Bool
        ) {
            let displayCoordinate = CoordTransform.wgs84ToGcj02(
                coordinate.coreLocationCoordinate
            )
            mapView.setRegion(
                MKCoordinateRegion(
                    center: displayCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                ),
                animated: animated
            )
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !hasCenteredOnUser,
                  parent.selectedCoordinate == nil,
                  parent.routeOverlay == nil,
                  let coordinate = userLocation.location?.coordinate else { return }

            hasCenteredOnUser = true
            mapView.setRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                ),
                animated: true
            )
        }

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            guard let routePolyline,
                  let polyline = overlay as? MKPolyline,
                  polyline === routePolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 6
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }

            let identifier: String
            let tintColor: UIColor
            let glyphText: String

            if annotation === routeStartPin {
                identifier = "route-start"
                tintColor = .systemGreen
                glyphText = "起"
            } else if annotation === routeEndPin {
                identifier = "route-end"
                tintColor = .systemRed
                glyphText = "终"
            } else {
                return nil
            }

            let annotationView = (
                mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    as? MKMarkerAnnotationView
            ) ?? MKMarkerAnnotationView(
                annotation: annotation,
                reuseIdentifier: identifier
            )
            annotationView.annotation = annotation
            annotationView.markerTintColor = tintColor
            annotationView.glyphText = glyphText
            annotationView.displayPriority = .required
            return annotationView
        }

        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            hasRenderedMap = true
            updateErrorMessage(nil)
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
            guard !hasRenderedMap else { return }
            updateErrorMessage("地图暂时无法载入，请检查网络或点此重试。")
        }

        private func updateErrorMessage(_ message: String?) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.errorMessage = message
            }
        }
    }
}
