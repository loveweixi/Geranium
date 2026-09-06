import MapKit
import SwiftUI

struct CustomMapView: UIViewRepresentable {
    @Binding var selectedCoordinate: SimulatedCoordinate?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.layer.cornerRadius = 14
        mapView.layer.masksToBounds = true

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

        guard let selectedCoordinate else { return }
        guard context.coordinator.lastRenderedCoordinate != selectedCoordinate else { return }

        let displayCoordinate = CoordTransform.wgs84ToGcj02(selectedCoordinate.coreLocationCoordinate)
        context.coordinator.selectionPin.coordinate = displayCoordinate

        if !mapView.annotations.contains(where: { $0 === context.coordinator.selectionPin }) {
            mapView.addAnnotation(context.coordinator.selectionPin)
        }

        mapView.setRegion(
            MKCoordinateRegion(
                center: displayCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ),
            animated: context.coordinator.lastRenderedCoordinate != nil
        )
        context.coordinator.lastRenderedCoordinate = selectedCoordinate
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CustomMapView
        let selectionPin = MKPointAnnotation()
        var lastRenderedCoordinate: SimulatedCoordinate?
        private var hasCenteredOnUser = false

        init(parent: CustomMapView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            let mapCoordinate = mapView.convert(point, toCoordinateFrom: mapView)
            let wgs84Coordinate = CoordTransform.gcj02ToWgs84(mapCoordinate)
            parent.selectedCoordinate = SimulatedCoordinate(wgs84Coordinate)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard !hasCenteredOnUser,
                  parent.selectedCoordinate == nil,
                  let coordinate = userLocation.location?.coordinate else { return }

            hasCenteredOnUser = true
            mapView.setRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                ),
                animated: true
            )
        }
    }
}
