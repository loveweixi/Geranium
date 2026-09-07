import MapKit
import SwiftUI
import UIKit

struct LocSimView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationAuthorization = LocationAuthorizationModel()
    @StateObject private var searchModel = LocationSearchModel()

    @State private var selectedCoordinate: SimulatedCoordinate?
    @State private var selectedName: String?
    @State private var activeCoordinate: SimulatedCoordinate?
    @State private var mapCameraTarget: MapCameraTarget?
    @State private var mapErrorMessage: String?
    @State private var mapIdentity = UUID()
    @State private var savedLocations: [SavedLocation] = []
    @State private var searchText = ""
    @State private var isShowingAddLocation = false
    @State private var isShowingFavorites = false
    @State private var status: Status = .waitingForSelection

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
                .ignoresSafeArea()

            CustomMapView(
                selectedCoordinate: $selectedCoordinate,
                selectedName: $selectedName,
                errorMessage: $mapErrorMessage,
                cameraTarget: mapCameraTarget
            )
            .id(mapIdentity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            VStack(spacing: 10) {
                searchPanel

                if let mapErrorMessage {
                    mapErrorBanner(mapErrorMessage)
                }

                Spacer(minLength: 120)

                controlPanel
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $isShowingAddLocation) {
            LocationEditorView(
                title: "添加位置",
                initialName: selectedName ?? "",
                initialCoordinate: selectedCoordinate
            ) { name, coordinate in
                savedLocations = SavedLocationStore.add(
                    name: name,
                    coordinate: coordinate
                )
                selectAndCenter(coordinate, name: name)
            }
        }
        .sheet(isPresented: $isShowingFavorites) {
            FavoriteLocationsView(
                locations: $savedLocations,
                onSelect: { location in
                    selectAndCenter(location.coordinate, name: location.name)
                }
            )
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

    private var searchPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("搜索地点或地址", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchModel.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }

                if searchModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        performSearch()
                    } label: {
                        Text("搜索")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if !searchModel.results.isEmpty {
                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchModel.results) { result in
                            Button {
                                selectSearchResult(result)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.accentColor)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if result.id != searchModel.results.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
            } else if let errorMessage = searchModel.errorMessage {
                Divider()
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }

    private var controlPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: selectedCoordinate == nil ? "hand.tap.fill" : "mappin.circle.fill")
                    .font(.title2)
                    .foregroundColor(selectedCoordinate == nil ? .secondary : .accentColor)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(
                                selectedCoordinate == nil
                                    ? Color.secondary.opacity(0.12)
                                    : Color.accentColor.opacity(0.14)
                            )
                    )

                if let selectedCoordinate {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedName ?? "已选位置")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(coordinateText(selectedCoordinate))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("选择一个位置")
                            .font(.subheadline.weight(.semibold))
                        Text("轻点地图、搜索或从收藏夹选择")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
                statusLabel
            }

            HStack(spacing: 10) {
                Button {
                    startSimulation()
                } label: {
                    Label("开始", systemImage: "location.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(selectedCoordinate == nil || activeCoordinate != nil)

                Button(role: .destructive) {
                    stopSimulation()
                } label: {
                    Label("结束", systemImage: "location.slash.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(activeCoordinate == nil)
            }

            HStack(spacing: 10) {
                panelActionButton(title: "添加位置", systemImage: "plus.circle.fill") {
                    isShowingAddLocation = true
                }

                panelActionButton(
                    title: "收藏夹",
                    systemImage: "star.fill",
                    badge: "\(savedLocations.count)"
                ) {
                    isShowingFavorites = true
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 560)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 16, y: 7)
    }

    private func mapErrorBanner(_ message: String) -> some View {
        Button {
            mapErrorMessage = nil
            mapIdentity = UUID()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: 560)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func panelActionButton(
        title: String,
        systemImage: String,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 42)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .waitingForSelection:
            EmptyView()
        case .ready:
            Text("就绪")
                .font(.caption)
                .foregroundColor(.secondary)
        case .simulating:
            Label("进行中", systemImage: "location.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.green)
        case .stopped:
            Text("已结束")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func performSearch() {
        searchModel.search(
            query: searchText,
            near: selectedCoordinate
        )
    }

    private func selectSearchResult(_ result: LocationSearchResult) {
        let coordinate = SimulatedCoordinate(
            CoordTransform.gcj02ToWgs84(result.coordinate)
        )
        searchText = ""
        searchModel.clear()
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        selectAndCenter(coordinate, name: result.name)
    }

    private func selectAndCenter(
        _ coordinate: SimulatedCoordinate,
        name: String? = nil
    ) {
        selectedCoordinate = coordinate
        selectedName = name
        mapCameraTarget = MapCameraTarget(coordinate: coordinate)
        if activeCoordinate == nil {
            status = .ready
        }
    }

    private func coordinateText(_ coordinate: SimulatedCoordinate) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    private func startSimulation() {
        guard activeCoordinate == nil, let selectedCoordinate else { return }
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

private struct FavoriteLocationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var locations: [SavedLocation]
    @State private var editingLocation: SavedLocation?

    let onSelect: (SavedLocation) -> Void

    var body: some View {
        NavigationView {
            Group {
                if locations.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "star.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("还没有收藏位置")
                            .font(.headline)
                        Text("点击“添加位置”保存当前位置，也可以手动输入坐标。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30)
                } else {
                    List {
                        ForEach(locations) { location in
                            HStack(spacing: 10) {
                                Button {
                                    onSelect(location)
                                    dismiss()
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
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    editingLocation = location
                                } label: {
                                    Image(systemName: "pencil.circle")
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("修改 \(location.name)")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    delete(location)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }

                                Button {
                                    editingLocation = location
                                } label: {
                                    Label("修改", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("已收藏的位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(item: $editingLocation) { location in
            LocationEditorView(
                title: "修改位置",
                initialName: location.name,
                initialCoordinate: location.coordinate
            ) { name, coordinate in
                locations = SavedLocationStore.update(
                    id: location.id,
                    name: name,
                    coordinate: coordinate
                )
            }
        }
    }

    private func delete(_ location: SavedLocation) {
        guard let index = locations.firstIndex(where: { $0.id == location.id }) else { return }
        locations = SavedLocationStore.delete(
            at: IndexSet(integer: index),
            from: locations
        )
    }

    private func coordinateText(_ coordinate: SimulatedCoordinate) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
}

private struct LocationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var latitudeText: String
    @State private var longitudeText: String
    @State private var validationMessage: String?

    let title: String
    let onSave: (String, SimulatedCoordinate) -> Void

    init(
        title: String,
        initialName: String,
        initialCoordinate: SimulatedCoordinate?,
        onSave: @escaping (String, SimulatedCoordinate) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _latitudeText = State(
            initialValue: initialCoordinate.map { String(format: "%.6f", $0.latitude) } ?? ""
        )
        _longitudeText = State(
            initialValue: initialCoordinate.map { String(format: "%.6f", $0.longitude) } ?? ""
        )
    }

    var body: some View {
        NavigationView {
            Form {
                Section("位置信息") {
                    TextField("名称", text: $name)
                    TextField("纬度（-90 至 90）", text: $latitudeText)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("经度（-180 至 180）", text: $longitudeText)
                        .keyboardType(.numbersAndPunctuation)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        validateAndSave()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func validateAndSave() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "请输入位置名称。"
            return
        }

        guard let latitude = parseCoordinate(latitudeText),
              let longitude = parseCoordinate(longitudeText),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            validationMessage = "请输入有效的纬度和经度。"
            return
        }

        onSave(
            trimmedName,
            SimulatedCoordinate(latitude: latitude, longitude: longitude)
        )
        dismiss()
    }

    private func parseCoordinate(_ text: String) -> Double? {
        Double(
            text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "，", with: ".")
                .replacingOccurrences(of: ",", with: ".")
        )
    }
}

private struct LocationSearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

private final class LocationSearchModel: ObservableObject {
    @Published private(set) var results: [LocationSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private var currentSearch: MKLocalSearch?

    func search(query: String, near coordinate: SimulatedCoordinate?) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clear()
            return
        }

        currentSearch?.cancel()
        results = []
        errorMessage = nil
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedQuery
        request.resultTypes = [.address, .pointOfInterest]

        if let coordinate {
            request.region = MKCoordinateRegion(
                center: CoordTransform.wgs84ToGcj02(coordinate.coreLocationCoordinate),
                span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
            )
        }

        let search = MKLocalSearch(request: request)
        currentSearch = search
        search.start { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self,
                      self.currentSearch === search else { return }

                self.currentSearch = nil
                self.isSearching = false

                if error != nil {
                    self.errorMessage = "搜索失败，请检查网络后重试。"
                    return
                }

                self.results = (response?.mapItems ?? []).prefix(12).map { item in
                    let placemark = item.placemark
                    let addressParts = [
                        placemark.thoroughfare,
                        placemark.locality,
                        placemark.administrativeArea,
                        placemark.country
                    ]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }

                    return LocationSearchResult(
                        name: item.name ?? "未命名地点",
                        subtitle: addressParts.joined(separator: " · "),
                        coordinate: placemark.coordinate
                    )
                }

                if self.results.isEmpty {
                    self.errorMessage = "没有找到匹配的地点。"
                }
            }
        }
    }

    func clear() {
        currentSearch?.cancel()
        currentSearch = nil
        results = []
        errorMessage = nil
        isSearching = false
    }
}
