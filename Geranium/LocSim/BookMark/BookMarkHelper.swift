import Foundation

struct SavedLocation: Identifiable, Equatable {
    let id: UUID
    let name: String
    let coordinate: SimulatedCoordinate
}

enum SavedLocationStore {
    static let suiteName = "group.live.cclerc.geraniumBookmarks"
    private static let storageKey = "bookmarks"

    static func load() -> [SavedLocation] {
        guard let records = defaults.array(forKey: storageKey) as? [[String: Any]] else {
            return []
        }

        return records.compactMap { record in
            guard let latitude = number(from: record["lat"]),
                  let longitude = number(from: record["long"]) else { return nil }

            let storedName = (record["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fallbackName = String(format: "%.5f, %.5f", latitude, longitude)
            let identifier = (record["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()

            return SavedLocation(
                id: identifier,
                name: storedName.isEmpty ? fallbackName : storedName,
                coordinate: SimulatedCoordinate(latitude: latitude, longitude: longitude)
            )
        }
    }

    static func add(name: String, coordinate: SimulatedCoordinate) -> [SavedLocation] {
        var locations = load()
        locations.append(
            SavedLocation(
                id: UUID(),
                name: displayName(for: name, coordinate: coordinate),
                coordinate: coordinate
            )
        )
        save(locations)
        return locations
    }

    static func update(
        id: UUID,
        name: String,
        coordinate: SimulatedCoordinate
    ) -> [SavedLocation] {
        var locations = load()
        guard let index = locations.firstIndex(where: { $0.id == id }) else {
            return locations
        }

        locations[index] = SavedLocation(
            id: id,
            name: displayName(for: name, coordinate: coordinate),
            coordinate: coordinate
        )
        save(locations)
        return locations
    }

    static func delete(at offsets: IndexSet, from locations: [SavedLocation]) -> [SavedLocation] {
        var updatedLocations = locations
        for index in offsets.sorted(by: >) {
            updatedLocations.remove(at: index)
        }
        save(updatedLocations)
        return updatedLocations
    }

    static func save(_ locations: [SavedLocation]) {
        let records = locations.map { location in
            [
                "id": location.id.uuidString,
                "name": location.name,
                "lat": location.coordinate.latitude,
                "long": location.coordinate.longitude
            ] as [String: Any]
        }
        defaults.set(records, forKey: storageKey)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static func number(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return value as? Double
    }

    private static func displayName(
        for name: String,
        coordinate: SimulatedCoordinate
    ) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty
            ? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
            : trimmedName
    }
}
