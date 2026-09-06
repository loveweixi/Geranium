import MapKit
import SwiftUI

enum MapDisplayState: Equatable {
    case ready
    case failed(String)
}

struct MapCameraTarget: Equatable {
    let id = UUID()
    let coordinate: SimulatedCoordinate
}

struct CustomMapView: UIViewRepresentable {
    @Binding var selectedCoordinate: SimulatedCoordinate?
    @Binding var displayState: MapDisplayState

    let cameraTarget: MapCameraTarget?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.mapType = .standard
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

        if let selectedCoordinate,
           context.coordinator.lastRenderedCoordinate != selectedCoordinate {
            context.coordinator.renderPin(
                for: selectedCoordinate,
                on: mapView
            )
        }

        if let cameraTarget,
           context.coordinator.lastCameraTargetID != cameraTarget.id {
            context.coordinator.lastCameraTargetID = cameraTarget.id
            context.coordinator.renderPin(
                for: cameraTarget.coordinate,
                on: mapView
            )
            context.coordinator.centerMap(
                on: cameraTarget.coordinate,
                mapView: mapView,
                animated: true
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CustomMapView
        let selectionPin = MKPointAnnotation()
        var lastRenderedCoordinate: SimulatedCoordinate?
        var lastCameraTargetID: UUID?

        private var hasCenteredOnUser = false
        private var hasLoadedMap = false

        init(parent: CustomMapView) {
            self.parent = parent
            selectionPin.title = "已选位置"
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            let mapCoordinate = mapView.convert(point, toCoordinateFrom: mapView)
            let wgs84Coordinate = CoordTransform.gcj02ToWgs84(mapCoordinate)
            parent.selectedCoordinate = SimulatedCoordinate(wgs84Coordinate)
        }

        func renderPin(
            for coordinate: SimulatedCoordinate,
            on mapView: MKMapView
        ) {
            selectionPin.coordinate = CoordTransform.wgs84ToGcj02(
                coordinate.coreLocationCoordinate
            )

            if !mapView.annotations.contains(where: { $0 === selectionPin }) {
                mapView.addAnnotation(selectionPin)
            }
            lastRenderedCoordinate = coordinate
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

        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            hasLoadedMap = true
            updateDisplayState(.ready)
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
            guard !hasLoadedMap else { return }
            updateDisplayState(.failed("地图加载失败，请检查网络后重试。"))
        }

        private func updateDisplayState(_ state: MapDisplayState) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.displayState = state
            }
        }
    }
}
