import Combine
import CoreLocation
import MapKit
import SwiftUI

struct CreateTripView: View {
    @State private var stops: [TripStop] = []
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isShowingStopsSheet = false
    @State private var stopsSheetDetent: PresentationDetent = .height(220)
    @State private var stopsSheetHeight: CGFloat = 220
    @StateObject private var locationProvider = UserLocationProvider()
    @State private var hasAddedUserStop = false

    private let cameraBreathingRoomRatio = 0.2

    var body: some View {
        GeometryReader { geometry in
            let markerViews = stops.map { stop in
                Marker(stop.label, coordinate: coordinate(for: stop))
            }
            let polylineViews = stops.indices.dropLast().map { index in
                MapPolyline(
                    geodesicPolyline(
                        from: coordinate(for: stops[index]),
                        to: coordinate(for: stops[index + 1])
                    )
                )
                .stroke(.blue, lineWidth: 4)
            }

            Map(position: $cameraPosition) {
                UserAnnotation()

                ForEach(Array(markerViews.enumerated()), id: \.offset) { _, marker in
                    marker
                }
                ForEach(Array(polylineViews.enumerated()), id: \.offset) { _, polyline in
                    polyline
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                isShowingStopsSheet = true
                locationProvider.requestLocation()
                updateCameraForStops(in: geometry.size, animated: false)
            }
            .onChange(of: stops) { _, _ in
                updateCameraForStops(in: geometry.size)
            }
            .onChange(of: stopsSheetHeight) { _, _ in
                updateCameraForStops(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, size in
                updateCameraForStops(in: size)
            }
        }
        .navigationTitle("Create Trip")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingStopsSheet) {
            CreateTripStopsSheet(stops: $stops, sheetHeight: $stopsSheetHeight, onAddStop: addStop)
                .presentationDetents([.height(220), .medium, .large], selection: $stopsSheetDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
        .onChange(of: locationProvider.location) { _, location in
            guard !hasAddedUserStop, let location else { return }
            hasAddedUserStop = true
            addUserLocationStop(location)
        }
    }

    private func coordinate(for stop: TripStop) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: stop.gps.latitude, longitude: stop.gps.longitude)
    }

    private func addStop(_ stop: TripStop) {
        stops.append(stop)
    }

    private func addUserLocationStop(_ location: CLLocation) {
        let stop = TripStop(
            label: "Current Location",
            gps: StopGPS(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracyMeters: location.horizontalAccuracy
            )
        )
        stops.insert(stop, at: 0)
    }

    private func geodesicPolyline(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> MKGeodesicPolyline {
        let coordinates = [start, end]
        return coordinates.withUnsafeBufferPointer { buffer in
            MKGeodesicPolyline(coordinates: buffer.baseAddress!, count: coordinates.count)
        }
    }

    private func updateCameraForStops(in mapSize: CGSize, animated: Bool = true) {
        guard !stops.isEmpty else {
            cameraPosition = .userLocation(fallback: .automatic)
            return
        }

        guard mapSize.width > 0, mapSize.height > 0 else {
            return
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .rect(offsetStopBounds(in: mapSize))
            }
        } else {
            cameraPosition = .rect(offsetStopBounds(in: mapSize))
        }
    }

    private func offsetStopBounds(in mapSize: CGSize) -> MKMapRect {
        let mapAspectRatio = Double(mapSize.width / mapSize.height)
        var cameraRect = aspectFittedRect(containing: paddedStopBounds(), aspectRatio: mapAspectRatio)
        let extraPaddingX = cameraRect.size.width * cameraBreathingRoomRatio
        let extraPaddingY = cameraRect.size.height * cameraBreathingRoomRatio

        cameraRect = cameraRect.insetBy(dx: -extraPaddingX, dy: -extraPaddingY)
        let coveredMapHeight = min(stopsSheetHeight, mapSize.height)
        let verticalOffset = cameraRect.size.height * Double(coveredMapHeight / mapSize.height) / 2

        cameraRect.origin.y += verticalOffset
        return cameraRect
    }

    private func aspectFittedRect(containing rect: MKMapRect, aspectRatio: Double) -> MKMapRect {
        guard aspectRatio > 0 else {
            return rect
        }

        var fittedRect = rect
        let rectAspectRatio = fittedRect.size.width / fittedRect.size.height

        if rectAspectRatio > aspectRatio {
            let targetHeight = fittedRect.size.width / aspectRatio
            fittedRect = fittedRect.insetBy(dx: 0, dy: -(targetHeight - fittedRect.size.height) / 2)
        } else {
            let targetWidth = fittedRect.size.height * aspectRatio
            fittedRect = fittedRect.insetBy(dx: -(targetWidth - fittedRect.size.width) / 2, dy: 0)
        }

        return fittedRect
    }

    private func paddedStopBounds() -> MKMapRect {
        guard stops.count > 1 else {
            let region = MKCoordinateRegion(
                center: coordinate(for: stops[0]),
                latitudinalMeters: 1_500,
                longitudinalMeters: 1_500
            )
            return mapRect(for: region)
        }

        var boundingRect = MKMapRect.null
        for stop in stops {
            boundingRect = boundingRect.union(mapRect(for: coordinate(for: stop)))
        }

        let paddingX = max(boundingRect.size.width * 0.25, 1_000)
        let paddingY = max(boundingRect.size.height * 0.25, 1_000)
        return boundingRect.insetBy(dx: -paddingX, dy: -paddingY)
    }

    private func mapRect(for coordinate: CLLocationCoordinate2D) -> MKMapRect {
        MKMapRect(
            origin: MKMapPoint(coordinate),
            size: MKMapSize(width: 1, height: 1)
        )
    }

    private func mapRect(for region: MKCoordinateRegion) -> MKMapRect {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2
        ))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2
        ))

        return MKMapRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(topLeft.x - bottomRight.x),
            height: abs(topLeft.y - bottomRight.y)
        )
    }
}

private struct CreateTripStopsSheet: View {
    @Binding var stops: [TripStop]
    @Binding var sheetHeight: CGFloat
    let onAddStop: (TripStop) -> Void

    @State private var isChoosingLocationSource = false
    @State private var addStopSheetDetent: PresentationDetent = .height(280)

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Stops")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isChoosingLocationSource = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline)
                        }
                        .accessibilityLabel("Add stop")
                    }
                }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        sheetHeight = geometry.size.height
                    }
                    .onChange(of: geometry.size.height) { _, height in
                        sheetHeight = height
                    }
            }
        }
        .sheet(
            isPresented: $isChoosingLocationSource,
            onDismiss: {
                addStopSheetDetent = .height(280)
            }
        ) {
            AddStopLocationSourceSheet(
                detent: $addStopSheetDetent,
                onAddStop: addStop
            )
                .presentationDetents([.height(280), .large], selection: $addStopSheetDetent)
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        List {
            if stops.isEmpty {
                EmptyStopsRow()
            } else {
                ForEach(stops) { stop in
                    TimelineStopRow(
                        stop: stop,
                        isFirst: stops.first?.id == stop.id,
                        isLast: stops.last?.id == stop.id
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if let index = stops.firstIndex(of: stop) {
                                stops.remove(at: index)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func addStop(_ stop: TripStop) {
        isChoosingLocationSource = false
        onAddStop(stop)
    }
}

private struct AddStopLocationSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var detent: PresentationDetent
    let onAddStop: (TripStop) -> Void

    @StateObject private var searchStore = LocationSearchStore()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add stop")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        List {
            if searchStore.trimmedQuery.isEmpty {
                Button {
                    dismiss()
                } label: {
                    Label("From calendar", systemImage: "calendar")
                }
            } else {
                searchResultsView
            }
        }
        .searchable(text: $searchStore.query, prompt: "Search for a place or address")
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .task {
            searchStore.prepareForSearch()
        }
        .onChange(of: searchStore.trimmedQuery) { _, query in
            detent = query.isEmpty ? .height(280) : .large
        }
    }

    @ViewBuilder
    private var searchResultsView: some View {
        if searchStore.isSearching {
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching...")
                    .foregroundStyle(.secondary)
            }
        }

        ForEach(searchStore.results) { result in
            Button {
                selectResult(result)
            } label: {
                LocationSearchResultRow(result: result)
            }
        }

        if let errorMessage = searchStore.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    private func selectResult(_ result: LocationSearchResult) {
        onAddStop(result.stop)
    }
}

private struct LocationSearchResult: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem
    let distanceFromUser: CLLocationDistance?

    var title: String {
        mapItem.displayName(fallback: "Selected location")
    }

    var subtitle: String {
        let placemark = mapItem.placemark

        return [
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea
        ]
        .compactMap { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        .joined(separator: ", ")
    }

    var distanceText: String? {
        guard let distanceFromUser else {
            return nil
        }

        let measurement = Measurement(value: distanceFromUser, unit: UnitLength.meters)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var stop: TripStop {
        TripStop(
            label: title,
            gps: StopGPS(
                latitude: mapItem.placemark.coordinate.latitude,
                longitude: mapItem.placemark.coordinate.longitude,
                horizontalAccuracyMeters: mapItem.placemark.location?.horizontalAccuracy
            )
        )
    }
}

private struct LocationSearchResultRow: View {
    let result: LocationSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let distanceText = result.distanceText {
                    Text(distanceText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private final class UserLocationProvider: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let location = locationManager.location, location.horizontalAccuracy >= 0 {
                self.location = location
            }
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            break
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            self.location = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in }
    }
}

@MainActor
private final class LocationSearchStore: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var query = ""
    @Published private(set) var results: [LocationSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let locationManager = CLLocationManager()
    private var cancellables: Set<AnyCancellable> = []
    private var searchTask: Task<Void, Never>?
    private var userLocation: CLLocation?

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override init() {
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        $query
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] query in
                self?.updateQuery(query)
            }
            .store(in: &cancellables)
    }

    func prepareForSearch() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            updateUserLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func reset() {
        query = ""
        results = []
        isSearching = false
        errorMessage = nil
        searchTask?.cancel()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            updateUserLocation()
        case .denied, .restricted:
            userLocation = nil
            search(trimmedQuery)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else {
                return
            }

            userLocation = location
            search(trimmedQuery)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            search(trimmedQuery)
        }
    }

    private func updateQuery(_ query: String) {
        errorMessage = nil
        search(query)
    }

    private func search(_ query: String) {
        guard !query.isEmpty else {
            searchTask?.cancel()
            results = []
            isSearching = false
            return
        }

        searchTask?.cancel()
        isSearching = true

        let searchLocation = userLocation

        searchTask = Task { [weak self] in
            do {
                let response = try await MKLocalSearch(request: Self.request(for: query, near: searchLocation)).start()
                guard !Task.isCancelled else { return }

                let results = Self.sortedResults(from: response.mapItems, userLocation: searchLocation)

                await MainActor.run {
                    self?.results = results
                    self?.isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self?.results = []
                    self?.isSearching = false
                    self?.errorMessage = "Search suggestions are unavailable."
                }
            }
        }
    }

    private func updateUserLocation() {
        if let location = locationManager.location, location.horizontalAccuracy >= 0 {
            userLocation = location
            search(trimmedQuery)
        }

        locationManager.requestLocation()
    }

    private static func request(for query: String, near userLocation: CLLocation?) -> MKLocalSearch.Request {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]

        if let userLocation {
            request.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 25_000,
                longitudinalMeters: 25_000
            )
        }

        return request
    }

    private static func sortedResults(
        from mapItems: [MKMapItem],
        userLocation: CLLocation?
    ) -> [LocationSearchResult] {
        mapItems
            .map { mapItem in
                LocationSearchResult(
                    mapItem: mapItem,
                    distanceFromUser: distance(from: userLocation, to: mapItem)
                )
            }
            .sorted { first, second in
                switch (first.distanceFromUser, second.distanceFromUser) {
                case let (firstDistance?, secondDistance?):
                    return firstDistance < secondDistance
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
                }
            }
    }

    private static func distance(from userLocation: CLLocation?, to mapItem: MKMapItem) -> CLLocationDistance? {
        guard let userLocation else {
            return nil
        }

        let destination = CLLocation(
            latitude: mapItem.placemark.coordinate.latitude,
            longitude: mapItem.placemark.coordinate.longitude
        )

        return userLocation.distance(from: destination)
    }
}

private extension MKMapItem {
    func displayName(fallback: String) -> String {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let name, !name.isEmpty {
            return name
        }

        return fallback
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct EmptyStopsRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No stops yet")
                .font(.headline)

            Text("Add stops to start planning a transit trip.")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct TripStopRow: View {
    let stop: TripStop

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stop.label)
                .font(.headline)

            Text(coordinateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let horizontalAccuracyMeters = stop.gps.horizontalAccuracyMeters {
                Text(accuracyText(horizontalAccuracyMeters))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var coordinateText: String {
        "\(stop.gps.latitude.formatted(.number.precision(.fractionLength(6)))), \(stop.gps.longitude.formatted(.number.precision(.fractionLength(6))))"
    }

    private func accuracyText(_ meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return "Accuracy: \(measurement.formatted(.measurement(width: .abbreviated, usage: .asProvided)))"
    }
}

// MARK: - TimelineStopRow
/// A view that displays a stop with a vertical timeline indicator.
/// It shows vertical lines above and below a circle containing a location pin icon,
/// visually connecting stops in a timeline style.
/// Parameters:
///  - stop: The TripStop data to display.
///  - isFirst: Whether this stop is the first in the list (no top line).
///  - isLast: Whether this stop is the last in the list (no bottom line).
private struct TimelineStopRow: View {
    let stop: TripStop
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline indicator
            VStack {
                // Top line
                if !isFirst {
                    Rectangle()
                        .foregroundStyle(.blue)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                        .frame(height: 16)
                }

                // Circle with icon
                ZStack {
                    Circle()
                        .strokeBorder(Color.blue, lineWidth: 2)
                        .background(Circle().foregroundColor(Color.blue.opacity(0.15)))
                        .frame(width: 32, height: 32)

                    Image(systemName: "mappin")
                        .foregroundStyle(.blue)
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(width: 32, height: 32)

                // Bottom line
                if !isLast {
                    Rectangle()
                        .foregroundStyle(.blue)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                        .frame(height: 16)
                }
            }
            .frame(width: 32)
            .padding(.top, 6)

            // Stop content
            TripStopRow(stop: stop)
        }
        .padding(.vertical, 6)
    }
}
