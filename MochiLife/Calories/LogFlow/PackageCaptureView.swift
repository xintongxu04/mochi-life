import PhotosUI
import SwiftUI

/// Reads the text on the front of a food package: a live camera preview from the rear
/// (world-facing) camera with a shutter (`PackageCamera`), whose photo is read like a chosen one;
/// choosing a photo from the library always works (also in the simulator). Images are processed
/// in memory only and never stored or uploaded.
///
/// The preview and the controls keep out of the safe area, the fold and the camera and status
/// occlusions (`foldAwareColumn`).
struct PackageCaptureView: View {
    /// Called with the recognized lines (and their letter heights), or not at all on Cancel.
    let onRecognized: ([PackageTextReader.Line]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = PackageCameraController()
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var message: String?

    private var hasCamera: Bool { PackageCamera.isAvailable }

    private var isCameraRunning: Bool { camera.status == .running }

    var body: some View {
        NavigationStack {
            ZStack {
                if hasCamera, case let .unavailable(reason) = camera.status {
                    unavailable(reason)
                } else if hasCamera {
                    PackageCameraPreview(controller: camera)
                        .accessibilityLabel("Camera view. Point at the front of the package.")
                        .overlay {
                            if camera.status == .starting { ProgressView() }
                        }
                } else {
                    unavailable("Choose a photo of the front of the package. It's read on this iPhone and never stored or uploaded.")
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
            // Preview and controls in one pane, clear of the fold and the occlusions.
            .foldAwareColumn(scrolls: false, limitsWidth: false, background: Color(uiColor: .systemBackground))
            .navigationTitle("Read Package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if hasCamera { await camera.start() }
            }
            .onDisappear { camera.stop() }
            .onChange(of: photoItem) {
                guard let photoItem else { return }
                Task {
                    if let data = try? await photoItem.loadTransferable(type: Data.self) { read(data) }
                    self.photoItem = nil
                }
            }
        }
    }

    private func unavailable(_ description: String) -> some View {
        ContentUnavailableView {
            Label("Read a Package", systemImage: "text.viewfinder")
        } description: {
            Text(description)
        }
    }

    private var controls: some View {
        HStack(spacing: 24) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Reads the text on a photo from your library")
            if hasCamera {
                Button {
                    takePhoto()
                } label: {
                    Image(systemName: "circle.inset.filled")
                        .font(.system(size: 64))
                        .frame(minWidth: 72, minHeight: 72)
                }
                .disabled(!isCameraRunning)
                .accessibilityLabel("Take Photo")
                .accessibilityHint("Takes a photo of the package and reads its text")
            }
        }
        .controlSize(.large)
        .disabled(isReading)
    }

    private func takePhoto() {
        message = nil
        Task {
            guard let data = await camera.capturePhoto() else {
                message = "The photo couldn't be taken. Hold the package steady and try again."
                return
            }
            read(data)
        }
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
