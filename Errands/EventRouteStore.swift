import CoreLocation
import MapKit
import SwiftUI

struct EventRouteSummary: Equatable {
    let expectedTravelTime: TimeInterval
    let distance: CLLocationDistance
}

@MainActor
final class EventRouteStore: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    enum State {
        case idle
        case requestingLocation(destination: MKMapItem)
        case geocoding
        case routing(destination: MKMapItem)
        case ready(destination: MKMapItem, route: MKRoute, summary: EventRouteSummary)
        case locationDenied(destination: MKMapItem)
        case destinationNotFound
        case currentLocationUnavailable(destination: MKMapItem)
        case routeUnavailable(destination: MKMapItem)
        case failed(String, destination: MKMapItem?)

        var destination: MKMapItem? {
            switch self {
            case .requestingLocation(let destination),
                 .routing(let destination),
                 .ready(let destination, _, _),
                 .locationDenied(let destination),
                 .currentLocationUnavailable(let destination),
                 .routeUnavailable(let destination):
                destination
            case .failed(_, let destination):
                destination
            case .idle, .geocoding, .destinationNotFound:
                nil
            }
        }

        var route: MKRoute? {
            if case .ready(_, let route, _) = self {
                route
            } else {
                nil
            }
        }

        var isLoading: Bool {
            switch self {
            case .requestingLocation, .geocoding, .routing:
                true
            case .idle, .ready, .locationDenied, .destinationNotFound, .currentLocationUnavailable, .routeUnavailable, .failed:
                false
            }
        }

        var loadingMessage: String {
            switch self {
            case .geocoding:
                "Finding location..."
            case .requestingLocation:
                "Checking your location..."
            case .routing:
                "Finding transit route..."
            case .idle, .ready, .locationDenied, .destinationNotFound, .currentLocationUnavailable, .routeUnavailable, .failed:
                ""
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var bottomInset: CGFloat = 0

    private let geocoder = CLGeocoder()
    private let locationManager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var loadedRouteKey: String?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func loadRoute(for event: DayCalendarEvent) async {
        await loadRoute(for: event, forceReload: false)
    }

    func reloadRoute(for event: DayCalendarEvent) async {
        await loadRoute(for: event, forceReload: true)
    }

    func openInMaps(for event: DayCalendarEvent) {
        if let destination = state.destination {
            openInMaps(destination)
            return
        }

        Task {
            do {
                let destination = try await geocodeDestination(for: event)
                openInMaps(destination)
            } catch {
                state = .destinationNotFound
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationContinuation?.resume(returning: manager.authorizationStatus)
        authorizationContinuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else {
                locationContinuation?.resume(throwing: CLError(.locationUnknown))
                locationContinuation = nil
                return
            }

            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }

    private func loadRoute(for event: DayCalendarEvent, forceReload: Bool) async {
        guard let location = event.location else {
            state = .failed("This event does not have a location.", destination: nil)
            return
        }

        let routeKey = "\(event.id)|\(location)"
        if !forceReload, loadedRouteKey == routeKey {
            return
        }

        loadedRouteKey = routeKey
        state = .geocoding

        do {
            let destination = try await geocodeDestination(for: event)
            guard !Task.isCancelled else { return }

            updateCamera(for: destination)

            let authorizationStatus = await requestLocationAuthorization(for: destination)
            guard !Task.isCancelled else { return }

            guard authorizationStatus.isAuthorizedForLocation else {
                state = .locationDenied(destination: destination)
                return
            }

            state = .requestingLocation(destination: destination)
            let currentLocation = try await requestCurrentLocation()
            guard !Task.isCancelled else { return }

            state = .routing(destination: destination)
            let route = try await route(from: currentLocation, to: destination)
            guard !Task.isCancelled else { return }

            let summary = EventRouteSummary(
                expectedTravelTime: route.expectedTravelTime,
                distance: route.distance
            )
            updateCamera(for: route, currentLocation: currentLocation, destination: destination)
            state = .ready(destination: destination, route: route, summary: summary)
        } catch RouteError.destinationNotFound {
            state = .destinationNotFound
        } catch RouteError.locationUnavailable(let destination) {
            state = .currentLocationUnavailable(destination: destination)
        } catch RouteError.routeUnavailable(let destination) {
            state = .routeUnavailable(destination: destination)
        } catch {
            state = .failed("Directions could not be loaded.", destination: state.destination)
        }
    }

    private func geocodeDestination(for event: DayCalendarEvent) async throws -> MKMapItem {
        guard let location = event.location else {
            throw RouteError.destinationNotFound
        }

        do {
            let placemarks = try await geocoder.geocodeAddressString(location)
            guard
                let placemark = placemarks.first,
                let coordinate = placemark.location?.coordinate
            else {
                throw RouteError.destinationNotFound
            }

            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            mapItem.name = placemark.name ?? event.title
            return mapItem
        } catch {
            throw RouteError.destinationNotFound
        }
    }

    private func requestLocationAuthorization(for destination: MKMapItem) async -> CLAuthorizationStatus {
        let status = locationManager.authorizationStatus

        switch status {
        case .authorizedAlways, .authorizedWhenInUse, .denied, .restricted:
            return status
        case .notDetermined:
            state = .requestingLocation(destination: destination)
            return await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return status
        }
    }

    private func requestCurrentLocation() async throws -> CLLocation {
        if let location = locationManager.location, location.horizontalAccuracy >= 0 {
            return location
        }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                locationContinuation = continuation
                locationManager.requestLocation()
            }
        } catch {
            guard let destination = state.destination else {
                throw error
            }

            throw RouteError.locationUnavailable(destination)
        }
    }

    private func route(from currentLocation: CLLocation, to destination: MKMapItem) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            placemark: MKPlacemark(coordinate: currentLocation.coordinate)
        )
        request.destination = destination
        request.transportType = .transit

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw RouteError.routeUnavailable(destination)
            }

            return route
        } catch {
            throw RouteError.routeUnavailable(destination)
        }
    }

    private func openInMaps(_ destination: MKMapItem) {
        destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit
        ])
    }

    private func updateCamera(for destination: MKMapItem) {
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let region = MKCoordinateRegion(
            center: destination.placemark.coordinate,
            span: span
        )
        let mapRect = mapRect(for: region)
        cameraPosition = .rect(mapRect)
    }

    private func updateCamera(for route: MKRoute, currentLocation: CLLocation, destination: MKMapItem) {
        var routeMapRect = route.polyline.boundingMapRect
        routeMapRect = routeMapRect.union(mapRect(for: currentLocation.coordinate))
        routeMapRect = routeMapRect.union(mapRect(for: destination.placemark.coordinate))

        if routeMapRect.size.width == 0 || routeMapRect.size.height == 0 {
            updateCamera(for: destination)
            return
        }

        let paddingX = routeMapRect.size.width * 0.2
        let paddingY = routeMapRect.size.height * 0.2
        let paddedRect = routeMapRect.insetBy(dx: -paddingX, dy: -paddingY)
        cameraPosition = .rect(paddedRect)
    }

    private func mapRect(for coordinate: CLLocationCoordinate2D) -> MKMapRect {
        MKMapRect(
            origin: MKMapPoint(coordinate),
            size: MKMapSize(width: 1, height: 1)
        )
    }

    private func mapRect(for region: MKCoordinateRegion) -> MKMapRect {
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                  longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                  longitude: region.center.longitude + region.span.longitudeDelta / 2))
        return MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
    }

    private enum RouteError: Error {
        case destinationNotFound
        case locationUnavailable(MKMapItem)
        case routeUnavailable(MKMapItem)
    }
}

private extension CLAuthorizationStatus {
    var isAuthorizedForLocation: Bool {
        self == .authorizedAlways || self == .authorizedWhenInUse
    }
}
