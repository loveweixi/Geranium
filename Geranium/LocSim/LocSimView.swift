import SwiftUI
import UIKit

struct LocSimView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationAuthorization = LocationAuthorizationModel()

    @State private var selectedCoordinate: SimulatedCoordinate?
    @State private var activeCoordinate: SimulatedCoordinate?
    @State private var savedLocations: [SavedLocation] = []
    @State private var isShowingCoordinateEditor = false
    @State private var isShowingFavoritePrompt = false
    @State private var favoriteName = ""
    @State private var status: Status = .waitingForSelection

    var body: some View {
        NavigationView {
            List {
                Section(footer: Text("Tap the map or enter coordinates")) {
                    CustomMapView(selectedCoordinate: $selectedCoordinate)
                        .frame(height: 300)
                        .listRowInsets(EdgeInsets())
                        .accessibilityLabel(Text("Location map"))
                }

                Section("Selected Location") {
                    coordinateSummary
                    actionButtons

                    Button {
                        favoriteName = ""
                        isShowingFavoritePrompt = true
                    } label: {
                        Label("Save Favorite", systemImage: "star")
                    }
                    .disabled(selectedCoordinate == nil)
                }

                Section(
                    header: Text("Favorites"),
                    footer: Text("Tap a favorite to load it above, then start simulation.")
                ) {
                    if savedLocations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No favorites yet")
                                .foregroundColor(.secondary)
                            Text("Select a location, then save it as a favorite.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(savedLocations) { location in
                            Button {
                                selectedCoordinate = location.coordinate
                                status = .ready
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.accentColor)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(location.name)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(.primary)
                                        Text(coordinateText(location.coordinate))
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if selectedCoordinate == location.coordinate {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            savedLocations = SavedLocationStore.delete(
                                at: offsets,
                                from: savedLocations
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Location Simulator")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingCoordinateEditor = true
                    } label: {
                        Label("Enter Coordinates", systemImage: "number")
                    }
                }
            }
            .sheet(isPresented: $isShowingCoordinateEditor) {
                CoordinateEditorView(initialCoordinate: selectedCoordinate) { coordinate in
                    selectedCoordinate = coordinate
                    status = .ready
                }
            }
            .alert("Save Favorite", isPresented: $isShowingFavoritePrompt) {
                TextField("Favorite name", text: $favoriteName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    saveSelectedLocation()
                }
            } message: {
                Text("Give this location a name.")
            }
            .onAppear {
                locationAuthorization.requestAuthorization()
                reloadSavedLocations()
            }
            .onChange(of: selectedCoordinate) { newCoordinate in
                guard newCoordinate != nil else { return }
                if activeCoordinate == nil {
                    status = .ready
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    reloadSavedLocations()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var coordinateSummary: some View {
        if let selectedCoordinate {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    coordinateLine(title: "Latitude", value: selectedCoordinate.latitude)
                    coordinateLine(title: "Longitude", value: selectedCoordinate.longitude)
                }
                Spacer()
                statusLabel
            }
        } else {
            Label("No location selected", systemImage: "mappin.slash")
                .foregroundColor(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                startSimulation()
            } label: {
                Label("Start Simulation", systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(selectedCoordinate == nil)

            Button(role: .destructive) {
                stopSimulation()
            } label: {
                Label("Stop Simulation", systemImage: "location.slash.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .waitingForSelection:
            EmptyView()
        case .ready:
            Label("Ready", systemImage: "circle")
                .font(.caption)
                .foregroundColor(.secondary)
        case .simulating:
            Label("Simulating", systemImage: "location.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.green)
        case .stopped:
            Label("Stopped", systemImage: "location.slash")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func coordinateLine(title: LocalizedStringKey, value: Double) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundColor(.secondary)
            Text(String(format: "%.6f", value))
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func coordinateText(_ coordinate: SimulatedCoordinate) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    private func startSimulation() {
        guard let selectedCoordinate else { return }
        LocSimManager.start(at: selectedCoordinate)
        activeCoordinate = selectedCoordinate
        status = .simulating
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func stopSimulation() {
        LocSimManager.stop()
        activeCoordinate = nil
        status = .stopped
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func saveSelectedLocation() {
        guard let selectedCoordinate else { return }
        savedLocations = SavedLocationStore.add(
            name: favoriteName,
            coordinate: selectedCoordinate
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func reloadSavedLocations() {
        savedLocations = SavedLocationStore.load()
    }

    private enum Status {
        case waitingForSelection
        case ready
        case simulating
        case stopped
    }
}

private struct CoordinateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var latitudeText: String
    @State private var longitudeText: String
    @State private var validationMessage: LocalizedStringKey?

    let onSave: (SimulatedCoordinate) -> Void

    init(
        initialCoordinate: SimulatedCoordinate?,
        onSave: @escaping (SimulatedCoordinate) -> Void
    ) {
        _latitudeText = State(
            initialValue: initialCoordinate.map { String(format: "%.6f", $0.latitude) } ?? ""
        )
        _longitudeText = State(
            initialValue: initialCoordinate.map { String(format: "%.6f", $0.longitude) } ?? ""
        )
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Coordinates") {
                    TextField("Latitude", text: $latitudeText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Longitude", text: $longitudeText)
                        .keyboardType(.numbersAndPunctuation)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Enter Coordinates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        validateAndSave()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func validateAndSave() {
        guard let latitude = Double(latitudeText),
              let longitude = Double(longitudeText),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            validationMessage = "Enter a valid latitude and longitude."
            return
        }

        onSave(SimulatedCoordinate(latitude: latitude, longitude: longitude))
        dismiss()
    }
}
