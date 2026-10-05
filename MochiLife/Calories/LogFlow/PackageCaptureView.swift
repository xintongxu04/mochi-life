import PhotosUI
import SwiftUI
import VisionKit

/// Reads the text on the front of a food package: live scanning with VisionKit's
/// DataScannerViewController where supported (a shutter freezes the text currently recognized),
/// otherwise a photo; choosing a photo from the library always works (also in the simulator).
/// Images are processed in memory only and never stored or uploaded.
struct PackageCaptureView: View {
    /// Called with the recognized lines (and their letter heights), or not at all on Cancel.
    let onRecognized: ([PackageTextReader.Line]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scanner = ScannerState()
    @State private var photoItem: PhotosPickerItem?
    @State private var isTakingPhoto = false
    @State private var isReading = false
    @State private var message: String?

    private var canScanLive: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if canScanLive {
                    LiveTextScanner(state: scanner)
                        .ignoresSafeArea()
                        .accessibilityLabel("Camera view. Point at the front of the package.")
                } else {
                    ContentUnavailableView {
                        Label("Read a Package", systemImage: "text.viewfinder")
                    } description: {
                        Text("Take or choose a photo of the front of the package. It's read on this iPhone and never stored or uploaded.")
                    }
                }
                VStack {
                    Spacer()
                    if isReading {
                        ProgressView("Reading the package…")
                            .padding()
                            .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    } else if let message {
                        Text(message)
                            .padding()
                            .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    }
                    controls
                }
                .padding()
            }
            .navigationTitle("Read Package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $isTakingPhoto) {
                CameraPicker { image in
                    if let data = image.jpegData(compressionQuality: 0.9) { read(data) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) {
                guard let photoItem else { return }
                Task {
                    if let data = try? await photoItem.loadTransferable(type: Data.self) { read(data) }
                    self.photoItem = nil
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 24) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Reads the text on a photo from your library")
            if canScanLive {
                Button {
                    finishLiveScan()
                } label: {
                    Image(systemName: "circle.inset.filled")
                        .font(.system(size: 64))
                        .frame(minWidth: 72, minHeight: 72)
                }
                .accessibilityLabel("Use the recognized text")
                .accessibilityHint("Freezes the text the camera is reading and looks for the food")
            } else if CameraPicker.isAvailable {
                Button("Take Photo", systemImage: "camera") { isTakingPhoto = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Takes a photo of the package to read its text")
            }
        }
        .controlSize(.large)
        .disabled(isReading)
    }

    private func finishLiveScan() {
        let lines = scanner.freeze()
        guard !lines.isEmpty else {
            message = "No text recognized yet. Hold the package steady and try again."
            return
        }
        onRecognized(lines)
        dismiss()
    }

    private func read(_ data: Data) {
        isReading = true
        message = nil
        Task {
            let lines = (try? await PackageTextReader.recognizedLines(in: data)) ?? []
            isReading = false
            if lines.isEmpty {
                message = "No text was found in the photo. Try another photo or type the name."
            } else {
                onRecognized(lines)
                dismiss()
            }
        }
    }
}

/// The text the live scanner currently sees, and whether scanning should stop.
@MainActor
@Observable
final class ScannerState {
    fileprivate var items: [RecognizedItem.ID: PackageTextReader.Line] = [:]
    fileprivate(set) var isFrozen = false

    /// Stops scanning and returns the recognized lines, tallest text first.
    func freeze() -> [PackageTextReader.Line] {
        isFrozen = true
        return items.values.sorted { $0.height > $1.height }
    }
}

/// VisionKit's live text scanner. Scanning stops when frozen or when the view goes away, so no
/// camera session is kept after dismissal.
private struct LiveTextScanner: UIViewControllerRepresentable {
    let state: ScannerState

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()], qualityLevel: .accurate, recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if state.isFrozen { scanner.stopScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let state: ScannerState
        init(state: ScannerState) { self.state = state }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            update(allItems, in: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) {
            update(allItems, in: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController, didRemove removed: [RecognizedItem], allItems: [RecognizedItem]) {
            update(allItems, in: scanner)
        }

        private func update(_ items: [RecognizedItem], in scanner: DataScannerViewController) {
            guard !state.isFrozen else { return }
            let viewHeight = max(scanner.view.bounds.height, 1)
            var lines: [RecognizedItem.ID: PackageTextReader.Line] = [:]
            for item in items {
                guard case let .text(text) = item else { continue }
                let bounds = item.bounds
                let height = abs(bounds.bottomLeft.y - bounds.topLeft.y) / viewHeight
                lines[item.id] = PackageTextReader.Line(text: text.transcript, height: Double(height))
            }
            state.items = lines
        }
    }
}
