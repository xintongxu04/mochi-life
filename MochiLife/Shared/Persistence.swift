import os
import SwiftData
import UIKit

/// The one place saved data is written. A failed save is logged and the owner is shown an
/// alert with Try Again (save again) or Discard Changes (undo the unsaved changes), so no save
/// ever fails silently.
@MainActor
enum Persistence {
    nonisolated static let logger = Logger(subsystem: "com.xintongxu.MochiLife", category: "persistence")

    /// Saves `context`. Returns true when the save worked; on failure shows an alert and
    /// returns false, so callers can keep a form open instead of closing it.
    @discardableResult
    static func save(_ context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
            showAlert(for: error, context: context)
            return false
        }
    }

    private static func showAlert(for error: Error, context: ModelContext) {
        let alert = UIAlertController(
            title: "Couldn't Save",
            message: "Your changes weren't saved. \(error.localizedDescription)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Discard Changes", style: .destructive) { _ in
            context.rollback()
            logger.notice("Unsaved changes discarded after a failed save")
        })
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { _ in
            save(context)
        })
        guard let presenter = topViewController() else {
            logger.fault("No screen to show the save error on")
            return
        }
        presenter.present(alert, animated: true)
    }

    /// The screen currently on top, including any open sheet, so the alert is always visible.
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
