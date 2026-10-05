import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Reports every touch anywhere in the app's window (sheets included) without taking part in
/// it: a window-level recognizer that never recognizes, never cancels or delays touches, and
/// works alongside every other gesture. Used to reset Mochi's inactivity timer.
struct TouchActivityReporter: UIViewRepresentable {
    let onTouch: @MainActor () -> Void

    func makeUIView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onTouch = onTouch
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ReporterView, context: Context) {
        view.onTouch = onTouch
    }

    final class ReporterView: UIView {
        var onTouch: (@MainActor () -> Void)?
        private var recognizer: TouchObserver?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, recognizer == nil else { return }
            let observer = TouchObserver { [weak self] in self?.onTouch?() }
            window.addGestureRecognizer(observer)
            recognizer = observer
        }
    }

    final class TouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
        private let handler: @MainActor () -> Void

        init(handler: @escaping @MainActor () -> Void) {
            self.handler = handler
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            delegate = self
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            handler()
            state = .failed
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
