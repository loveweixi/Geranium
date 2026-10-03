import MapKit
import SwiftUI
import UIKit

struct LocSimView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationAuthorization = LocationAuthorizationModel()
    @StateObject private var searchModel = LocationSearchModel()

    @State private var interactionMode: InteractionMode = .point
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

    @State private var routeStart: RouteWaypoint?
    @State private var routeDestination: RouteWaypoint?
    @State private var routeTransportMode: RouteTransportMode = .driving
    @State private var routePlan: RouteSimulationPlan?
    @State private var routeState: RouteState = .idle
    @State private var routeErrorMessage: String?
    @State private var routeEndpointTarget: RouteEndpointTarget?
    @State private var activeRouteSession: ActiveRouteSession?
    @State private var currentDirections: MKDirections?
    @State private var routeRequestID: UUID?

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
                .ignoresSafeArea()

            CustomMapView(
                selectedCoordinate: $selectedCoordinate,
                selectedName: $selectedName,
                errorMessage: $mapErrorMessage,
                cameraTarget: mapCameraTarget,
                routeOverlay: currentRouteOverlay
            )
            .id(mapIdentity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            VStack(spacing: 10) {
                if interactionMode == .point {
                    searchPanel
                }

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
        .sheet(item: $routeEndpointTarget) { target in
            RouteEndpointSearchView(
                target: target,
                nearbyCoordinate: routeSearchAnchor(for: target),
                mapSelection: selectedCoordinate,
                savedLocations: savedLocations
            ) { waypoint in
                setRouteEndpoint(target, waypoint: waypoint)
            }
        }
        .onAppear {
            locationAuthorization.requestAuthorization()
            reloadSavedLocations()
            restoreRouteSessionIfNeeded()
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
                restoreRouteSessionIfNeeded()
            }
        }
        .onChange(of: routeTransportMode) { _ in
            recalculateRouteIfPossible()
        }
        .onChange(of: interactionMode) { newMode in
            guard newMode == .route,
                  routeStart == nil,
                  let selectedCoordinate else { return }
            routeStart = RouteWaypoint(
                name: selectedName ?? "地图选点",
                coordinate: CoordTransform.wgs84ToGcj02(
                    selectedCoordinate.coreLocationCoordinate
                )
            )
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
            Picker("模拟方式", selection: $interactionMode) {
                ForEach(InteractionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isAnySimulationActive)

            if interactionMode == .point {
                pointControlContent
            } else {
                routeControlContent
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

    private var pointControlContent: some View {
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

            HStack(spacing: 8) {
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

                Button {
                    restoreRealLocation()
                } label: {
                    Label("恢复", systemImage: "location.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
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
    }

    @ViewBuilder
    private var routeControlContent: some View {
        if let activeRouteSession {
            activeRouteContent(activeRouteSession)
        } else {
            routeDraftContent
        }
    }

    private var routeDraftContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    routeEndpointButton(
                        title: "起点",
                        waypoint: routeStart,
                        color: .green
                    ) {
                        routeEndpointTarget = .start
                    }
                    .disabled(routeState == .starting)

                    Divider()
                        .padding(.leading, 38)

                    routeEndpointButton(
                        title: "终点",
                        waypoint: routeDestination,
                        color: .red
                    ) {
                        routeEndpointTarget = .destination
                    }
                    .disabled(routeState == .starting)
                }
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.76))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    swapRouteEndpoints()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.headline)
                        .frame(width: 40, height: 82)
                }
                .buttonStyle(.bordered)
                .disabled(
                    (routeStart == nil && routeDestination == nil)
                        || routeState == .starting
                )
                .accessibilityLabel("交换起点和终点")
            }

            Picker("出行方式", selection: $routeTransportMode) {
                ForEach(RouteTransportMode.allCases) { mode in
                    Label(
                        mode.displayName,
                        systemImage: mode == .driving ? "car.fill" : "figure.walk"
                    )
                    .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(routeState == .calculating || routeState == .starting)

            if let routeErrorMessage {
                Label(routeErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let routePlan {
                HStack(spacing: 8) {
                    Label(formatDistance(routePlan.distance), systemImage: "map")
                    Text("·")
                        .foregroundColor(.secondary)
                    Label(
                        "预计 \(formatDuration(routePlan.expectedTravelTime))",
                        systemImage: "clock"
                    )
                    Spacer()
                }
                .font(.subheadline.weight(.medium))

                HStack(spacing: 8) {
                    routePrimaryButton(
                        title: routeState == .starting ? "正在启动" : "开始",
                        systemImage: routeState == .starting ? "hourglass" : "location.fill",
                        color: .green
                    ) {
                        startRouteSimulation()
                    }
                    .disabled(routeState == .starting)

                    Button {
                        calculateRoute()
                    } label: {
                        Label("重算", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .disabled(routeState == .starting)
                }
            } else if routeState == .calculating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在规划路线…")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .frame(minHeight: 46)
            } else {
                routePrimaryButton(
                    title: "规划路线",
                    systemImage: "map.fill",
                    color: .blue
                ) {
                    calculateRoute()
                }
                .disabled(routeStart == nil || routeDestination == nil)
            }
        }
    }

    private func activeRouteContent(_ session: ActiveRouteSession) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: session.transportMode == .driving ? "car.fill" : "figure.walk")
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.green.opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(session.startName.isEmpty ? "起点" : session.startName) → \(session.destinationName.isEmpty ? "终点" : session.destinationName)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(formatDistance(session.distance)) · \(session.transportMode.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            }

            TimelineView(.periodic(from: Date(), by: 1)) { context in
                VStack(spacing: 6) {
                    HStack {
                        Text(context.date >= session.expectedArrivalAt ? "已到达" : "进行中")
                            .fontWeight(.semibold)
                            .foregroundColor(
                                context.date >= session.expectedArrivalAt ? .blue : .green
                            )
                        Spacer()
                        Text(routeRemainingText(session, at: context.date))
                    }
                    .font(.caption)

                    ProgressView(value: session.progress(at: context.date))
                        .tint(context.date >= session.expectedArrivalAt ? .blue : .green)

                    Text("进度 \(Int(session.progress(at: context.date) * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 8) {
                routePrimaryButton(title: "结束", systemImage: "location.slash.fill", color: .red) {
                    stopRouteSimulation()
                }
                routePrimaryButton(title: "恢复", systemImage: "location.circle.fill", color: .blue) {
                    restoreRealLocation()
                }
            }
        }
    }

    private func routeEndpointButton(
        title: String,
        waypoint: RouteWaypoint?,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(routeWaypointName(waypoint))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(waypoint == nil ? .secondary : .primary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func routePrimaryButton(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }

    private func routeWaypointName(_ waypoint: RouteWaypoint?) -> String {
        guard let waypoint, !waypoint.name.isEmpty else { return "请选择" }
        return waypoint.name
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
        case .restored:
            Label("已恢复", systemImage: "location.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.blue)
        }
    }

    private var currentRouteOverlay: MapRouteOverlay? {
        guard interactionMode == .route else { return nil }
        if let routePlan {
            return MapRouteOverlay(
                id: routePlan.id,
                displayCoordinates: routePlan.displayCoordinates
            )
        }
        guard let activeRouteSession,
              activeRouteSession.routeDisplayCoordinates.count >= 2 else { return nil }
        return MapRouteOverlay(
            id: activeRouteSession.id,
            displayCoordinates: activeRouteSession.routeDisplayCoordinates.map(
                \.coreLocationCoordinate
            )
        )
    }

    private var isAnySimulationActive: Bool {
        activeCoordinate != nil || activeRouteSession != nil || routeState == .starting
    }

    private func routeSearchAnchor(
        for target: RouteEndpointTarget
    ) -> SimulatedCoordinate? {
        let oppositeEndpoint = target == .start ? routeDestination : routeStart
        guard let oppositeEndpoint else { return selectedCoordinate }
        return SimulatedCoordinate(
            CoordTransform.gcj02ToWgs84(oppositeEndpoint.coordinate)
        )
    }

    private func setRouteEndpoint(
        _ target: RouteEndpointTarget,
        waypoint: RouteWaypoint
    ) {
        switch target {
        case .start:
            routeStart = waypoint
        case .destination:
            routeDestination = waypoint
        }
        recalculateRouteIfPossible()
    }

    private func swapRouteEndpoints() {
        let oldStart = routeStart
        routeStart = routeDestination
        routeDestination = oldStart
        recalculateRouteIfPossible()
    }

    private func recalculateRouteIfPossible() {
        invalidateRoutePlan()
        guard routeStart != nil, routeDestination != nil else { return }
        calculateRoute()
    }

    private func invalidateRoutePlan() {
        guard activeRouteSession == nil, routeState != .starting else { return }
        currentDirections?.cancel()
        currentDirections = nil
        routeRequestID = nil
        routePlan = nil
        routeErrorMessage = nil
        routeState = .idle
    }

    private func calculateRoute() {
        guard let routeStart, let routeDestination else { return }

        currentDirections?.cancel()
        routePlan = nil
        routeErrorMessage = nil
        routeState = .calculating
        let requestID = UUID()
        routeRequestID = requestID

        currentDirections = RouteSimulationPlanner.calculateRoute(
            from: routeStart,
            to: routeDestination,
            mode: routeTransportMode
        ) { result in
            DispatchQueue.main.async {
                guard routeRequestID == requestID else { return }
                currentDirections = nil
                routeRequestID = nil

                switch result {
                case .success(let plan):
                    routePlan = plan
                    routeState = .ready
                case .failure(let error):
                    routeErrorMessage = error.localizedDescription
                    routeState = .idle
                }
            }
        }
    }

    private func startRouteSimulation() {
        guard activeCoordinate == nil,
              activeRouteSession == nil,
              let routePlan else { return }

        routeState = .starting
        routeErrorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let session = try LocSimManager.start(route: routePlan)
                DispatchQueue.main.async {
                    activeRouteSession = session
                    routeState = .active
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    routeErrorMessage = error.localizedDescription
                    routeState = .ready
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func stopRouteSimulation() {
        LocSimManager.stopRoute()
        activeRouteSession = nil
        routeState = routePlan == nil ? .stopped : .ready
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func restoreRouteSessionIfNeeded() {
        guard activeRouteSession == nil,
              let persistedSession = LocSimManager.activeRouteSession else { return }
        activeRouteSession = persistedSession
        interactionMode = .route
        routeState = persistedSession.isEstimatedComplete ? .arrived : .active
    }

    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1_000 {
            return "\(Int(distance.rounded())) 米"
        }
        return String(format: "%.1f 公里", distance / 1_000)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(1, Int(ceil(duration / 60)))
        if totalMinutes < 60 {
            return "\(totalMinutes) 分钟"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分钟"
    }

    private func routeRemainingText(
        _ session: ActiveRouteSession,
        at date: Date
    ) -> String {
        let remaining = max(0, session.expectedArrivalAt.timeIntervalSince(date))
        return remaining > 0 ? "剩余约 \(formatDuration(remaining))" : "已到达终点"
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
        guard activeCoordinate == nil,
              activeRouteSession == nil,
              let selectedCoordinate else { return }
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

    private func restoreRealLocation() {
        LocSimManager.restoreRealLocation()
        activeCoordinate = nil
        activeRouteSession = nil
        selectedCoordinate = nil
        selectedName = nil
        routePlan = nil
        routeErrorMessage = nil
        routeState = .restored
        mapCameraTarget = MapCameraTarget(coordinate: nil)
        status = .restored
        locationAuthorization.requestAuthorization()
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
        case restored
    }
}

private enum InteractionMode: String, CaseIterable, Identifiable {
    case point
    case route

    var id: String { rawValue }

    var title: String {
        switch self {
        case .point:
            return "定点"
        case .route:
            return "轨迹"
        }
    }
}

private enum RouteEndpointTarget: String, Identifiable {
    case start
    case destination

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start:
            return "选择起点"
        case .destination:
            return "选择终点"
        }
    }
}

private enum RouteState: Equatable {
    case idle
    case calculating
    case ready
    case starting
    case active
    case arrived
    case stopped
    case restored
}

private struct RouteEndpointSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchModel = LocationSearchModel()
    @State private var query = ""

    let target: RouteEndpointTarget
    let nearbyCoordinate: SimulatedCoordinate?
    let mapSelection: SimulatedCoordinate?
    let savedLocations: [SavedLocation]
    let onSelect: (RouteWaypoint) -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索地点或地址", text: $query)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit(performSearch)

                    if !query.isEmpty {
                        Button {
                            query = ""
                            searchModel.clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if searchModel.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("搜索", action: performSearch)
                            .font(.subheadline.weight(.semibold))
                            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground))

                List {
                    if let mapSelection {
                        Section("地图") {
                            Button {
                                select(
                                    name: "地图当前选点",
                                    coordinate: CoordTransform.wgs84ToGcj02(
                                        mapSelection.coreLocationCoordinate
                                    )
                                )
                            } label: {
                                Label("使用地图当前选点", systemImage: "mappin.circle.fill")
                            }
                        }
                    }

                    if !savedLocations.isEmpty {
                        Section("收藏夹") {
                            ForEach(savedLocations) { location in
                                Button {
                                    select(
                                        name: location.name,
                                        coordinate: CoordTransform.wgs84ToGcj02(
                                            location.coordinate.coreLocationCoordinate
                                        )
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(location.name)
                                            .foregroundColor(.primary)
                                        Text(coordinateText(location.coordinate))
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if !searchModel.results.isEmpty {
                        Section("搜索结果") {
                            ForEach(searchModel.results) { result in
                                Button {
                                    select(name: result.name, coordinate: result.coordinate)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .foregroundColor(.accentColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.name)
                                                .foregroundColor(.primary)
                                            if !result.subtitle.isEmpty {
                                                Text(result.subtitle)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else if let errorMessage = searchModel.errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "magnifyingglass")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func performSearch() {
        searchModel.search(query: query, near: nearbyCoordinate)
    }

    private func select(name: String, coordinate: CLLocationCoordinate2D) {
        onSelect(RouteWaypoint(name: name, coordinate: coordinate))
        dismiss()
    }

    private func coordinateText(_ coordinate: SimulatedCoordinate) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
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
