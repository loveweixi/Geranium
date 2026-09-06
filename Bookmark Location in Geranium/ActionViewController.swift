import UIKit
import UniformTypeIdentifiers

final class ActionViewController: UIViewController {
    @IBOutlet private weak var textField: UITextField!

    private let suiteName = "group.live.cclerc.geraniumBookmarks"
    private let storageKey = "bookmarks"

    @IBAction private func saveButtonPressed(_ sender: UIButton) {
        sender.isEnabled = false

        guard let provider = firstURLProvider() else {
            sender.isEnabled = true
            presentError("No map location was found in the shared item.")
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self, weak sender] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let url = item as? URL,
                      let coordinate = self.coordinate(from: url) else {
                    sender?.isEnabled = true
                    self.presentError("This link does not contain usable coordinates.")
                    return
                }

                self.save(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    name: self.textField.text ?? ""
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.done()
            }
        }
    }

    @IBAction private func done() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func firstURLProvider() -> NSItemProvider? {
        let items = extensionContext?.inputItems as? [NSExtensionItem]
        return items?
            .compactMap(\.attachments)
            .flatMap { $0 }
            .first { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }
    }

    private func coordinate(from url: URL) -> (latitude: Double, longitude: Double)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let value = components.queryItems?.first(where: { $0.name == "ll" })?.value else {
            return nil
        }

        let parts = value.split(separator: ",", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }

        return (latitude, longitude)
    }

    private func save(latitude: Double, longitude: Double, name: String) {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        var records = defaults.array(forKey: storageKey) as? [[String: Any]] ?? []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty
            ? String(format: "%.5f, %.5f", latitude, longitude)
            : trimmedName

        records.append([
            "id": UUID().uuidString,
            "name": displayName,
            "lat": latitude,
            "long": longitude
        ])
        defaults.set(records, forKey: storageKey)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "Unable to Save", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
