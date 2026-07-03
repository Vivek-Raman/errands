import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct EventDetailView: View {
    let event: DayCalendarEvent

    @StateObject private var routeStore = EventRouteStore()

    var body: some View {
        List {
            eventSection
            mapSection
            routeSection
        }
        .navigationTitle("Directions")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: event.id) {
            await routeStore.loadRoute(for: event)
        }
    }

    private var eventSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(eventTime, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(event.title)
                    .font(.title2.bold())

                if let calendarTitle = event.calendarTitle {
                    Text(calendarTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var mapSection: some View {
        Section {
            ZStack {
                Map(position: $routeStore.cameraPosition) {
                    UserAnnotation()

                    if let destination = routeStore.state.destination {
                        Marker(
                            destination.name ?? "Destination",
                            coordinate: destination.placemark.coordinate
                        )
                    }

                    if let route = routeStore.state.route {
                        MapPolyline(route.polyline)
                            .stroke(.blue, lineWidth: 5)
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if routeStore.state.isLoading {
                    loadingOverlay
                }
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }

    @ViewBuilder
    private var routeSection: some View {
        Section("Transit") {
            switch routeStore.state {
            case .idle, .geocoding, .requestingLocation, .routing:
                Label(routeStore.state.loadingMessage.nilIfEmpty ?? "Loading directions...", systemImage: "tram")
                    .foregroundStyle(.secondary)
            case .ready(_, _, let summary):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Transit route found", systemImage: "tram.fill")
                    Text(routeSummary(summary))
                        .foregroundStyle(.secondary)
                }
                openInMapsButton
            case .locationDenied:
                Label("Location permission is off. Enable it in Settings to show a route from your current location.", systemImage: "location.slash")
                    .foregroundStyle(.secondary)
                settingsButton
                openInMapsButton
            case .destinationNotFound:
                Label("Location not found.", systemImage: "mappin.slash")
                    .foregroundStyle(.secondary)
            case .currentLocationUnavailable:
                Label("Your current location could not be found.", systemImage: "location.slash")
                    .foregroundStyle(.secondary)
                retryButton
                openInMapsButton
            case .routeUnavailable:
                Label("Transit directions are unavailable for this location.", systemImage: "tram")
                    .foregroundStyle(.secondary)
                openInMapsButton
            case .failed(let message, let destination):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                retryButton
                if destination != nil {
                    openInMapsButton
                }
            }
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(routeStore.state.loadingMessage.nilIfEmpty ?? "Loading directions...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var openInMapsButton: some View {
        Button {
            routeStore.openInMaps(for: event)
        } label: {
            Label("Open in Maps", systemImage: "map")
        }
        .buttonStyle(.borderedProminent)
    }

    private var retryButton: some View {
        Button {
            Task {
                await routeStore.reloadRoute(for: event)
            }
        } label: {
            Label("Retry", systemImage: "arrow.clockwise")
        }
    }

    private var settingsButton: some View {
        Button {
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                return
            }

            UIApplication.shared.open(settingsURL)
        } label: {
            Label("Open Settings", systemImage: "gear")
        }
    }

    private var eventTime: String {
        if event.isAllDay {
            return "All day"
        }

        return "\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))"
    }

    private func routeSummary(_ summary: EventRouteSummary) -> String {
        let travelTime = Duration.seconds(summary.expectedTravelTime)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
        let distance = Measurement(value: summary.distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))

        return "\(travelTime) · \(distance)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
