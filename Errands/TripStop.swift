import Foundation

struct TripStop: Identifiable, Hashable, Codable {
    let id: UUID
    var label: String
    var gps: StopGPS

    init(
        id: UUID = UUID(),
        label: String,
        gps: StopGPS
    ) {
        self.id = id
        self.label = label
        self.gps = gps
    }
}

struct StopGPS: Hashable, Codable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracyMeters: Double?

    init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
    }
}
