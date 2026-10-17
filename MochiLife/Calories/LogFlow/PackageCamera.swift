import AVFoundation
import AVKit
import Synchronization
import SwiftUI
import UIKit

/// The camera behind package scanning: one capture session on its own queue, using the rear
/// (world-facing) wide camera, with photo capture.
///
/// On iPhone Duo, opening, closing or turning the phone can change which physical camera faces
/// away from the screen, so the camera is chosen by facing direction (`PackageCameraController`)
/// and the session is rebuilt whenever that changes or the session is interrupted or fails.
actor PackageCamera {
    private let queue = DispatchSerialQueue(label: "com.xintongxu.MochiLife.packageCamera")
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// Shared with the preview layer on the main actor, which only reads it; the session is only
    /// configured, started and stopped on this actor's queue.
    nonisolated(unsafe) let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    /// Kept alive until its photo arrives.
    private var pendingCapture: PhotoCapture?

    /// There's a rear camera at all (false in the simulator).
    nonisolated static var isAvailable: Bool { fallbackDevice != nil }

    /// The rear wide-angle camera, for when facing-direction information isn't available.
    nonisolated private static var fallbackDevice: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    var isRunning: Bool { session.isRunning }

    /// Configures the session for the camera with `uniqueID` (else the rear wide-angle camera)
    /// and starts it. `rebuild` reconfigures even if that camera is already in use, after a
    /// failure. Returns the camera's unique ID, or nil if no camera could be used.
    func start(uniqueID: String?, rebuild: Bool = false) -> String? {
        guard let device = uniqueID.flatMap(AVCaptureDevice.init(uniqueID:)) ?? Self.fallbackDevice else { return nil }
        let deviceID = device.uniqueID
        let isNewCamera = input?.device.uniqueID != deviceID
        if rebuild || isNewCamera || session.inputs.isEmpty {
            guard configure(with: device) else { return nil }
        }
        if !session.isRunning { session.startRunning() }
        return deviceID
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }

    /// Takes a photo, upright for `rotationAngle` (from the rotation coordinator), as JPEG data.
    func capturePhoto(rotationAngle: CGFloat) async -> Data? {
        guard session.isRunning, pendingCapture == nil else { return nil }
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        let data = await withCheckedContinuation { continuation in
            let capture = PhotoCapture(continuation: continuation)
            pendingCapture = capture
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: capture)
        }
        pendingCapture = nil
        return data
    }

    private func configure(with device: AVCaptureDevice) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        input = nil
        guard let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) else { return false }
        session.addInput(newInput)
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
        guard session.canAddOutput(photoOutput) else { return false }
        session.addOutput(photoOutput)
        input = newInput
        return true
    }
}

/// Receives one photo and hands back its JPEG data once (nil on failure).
private final class PhotoCapture: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    private let continuation: Mutex<CheckedContinuation<Data?, Never>?>

    init(continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = Mutex(continuation)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        finish(error == nil ? photo.fileDataRepresentation() : nil)
    }

    /// Always called last; covers a capture that failed before producing a photo.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: (any Error)?) {
        finish(nil)
    }

    private func finish(_ data: Data?) {
        continuation.withLock { $0.take() }?.resume(returning: data)
    }
}

/// Runs the package camera for the capture screen: permission, choosing the camera by facing
/// direction, keeping the preview upright, and recovering after a pose change.
///
/// - **Choosing the camera:** on iOS 27.1, `AVCaptureDeviceDirectionCoordinator` reports the
///   wide cameras facing away from the preview (`backwardFacingDeviceDescriptors`), and the first
///   is used; when that set changes (iPhone Duo opened, closed or turned) the session switches to
///   the new camera. Before iOS 27.1, or until the coordinator first reports, the rear
///   wide-angle camera.
/// - **Recovery:** an interruption ending restarts the session; a runtime error, a disconnected
///   camera or finding the session stopped after a layout change rebuilds it, so the preview
///   comes back instead of staying black.
@MainActor
@Observable
final class PackageCameraController {
    enum Status: Equatable {
        case starting
        case running
        case unavailable(String)
    }

    private(set) var status = Status.starting
    @ObservationIgnored let camera = PackageCamera()
    @ObservationIgnored private weak var previewView: CameraPreviewView?
    /// `AVCaptureDeviceDirectionCoordinator` on iOS 27.1 (stored untyped for older systems).
    @ObservationIgnored private var directionCoordinator: AnyObject?
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    /// The world-facing camera reported by the direction coordinator.
    @ObservationIgnored private var preferredCameraID: String?
    /// The camera the session is using.
    @ObservationIgnored private var activeCameraID: String?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var isStopped = false

    static let cameraOffMessage = "Camera access is off for Mochi Life. Choose a photo instead, or allow the camera in Settings."
    static let failedMessage = "The camera couldn't be started. Choose a photo instead."

    /// Connects the preview, starts watching camera directions and session events.
    func attach(_ view: CameraPreviewView) {
        previewView = view
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onLayout = { [weak self] in self?.layoutChanged() }
        if #available(iOS 27.1, *) {
            let coordinator = AVCaptureDeviceDirectionCoordinator(view: view, deviceTypes: [.builtInWideAngleCamera]) { [weak self] directions in
                self?.directionsChanged(backwardFacing: directions.backwardFacingDeviceDescriptors.first?.uniqueID)
            }
            directionCoordinator = coordinator
            preferredCameraID = coordinator.deviceDirections.backwardFacingDeviceDescriptors.first?.uniqueID
        }
        observeSession()
    }

    /// Asks for camera permission if needed, then starts the session.
    func start() async {
        isStopped = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .unavailable(Self.cameraOffMessage)
                return
            }
        default:
            status = .unavailable(Self.cameraOffMessage)
            return
        }
        await restart(rebuild: false)
    }

    /// Stops the session and every observer; the camera is released when the screen closes.
    func stop() {
        isStopped = true
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        directionCoordinator = nil
        rotationCoordinator = nil
        let camera = camera
        Task { await camera.stop() }
    }

    /// A photo from the live camera, upright, as JPEG data.
    func capturePhoto() async -> Data? {
        let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
        return await camera.capturePhoto(rotationAngle: angle)
    }

    // MARK: - Recovery

    private func restart(rebuild: Bool) async {
        guard !isStopped else { return }
        guard let cameraID = await camera.start(uniqueID: preferredCameraID, rebuild: rebuild) else {
            status = .unavailable(Self.failedMessage)
            return
        }
        guard !isStopped else { return }
        if cameraID != activeCameraID || rotationCoordinator == nil {
            activeCameraID = cameraID
            makeRotationCoordinator(for: cameraID)
        }
        updatePreviewRotation()
        status = .running
    }

    /// The world-facing camera changed (iPhone Duo opened, closed or turned): switch to it.
    private func directionsChanged(backwardFacing cameraID: String?) {
        guard let cameraID, cameraID != preferredCameraID else { return }
        preferredCameraID = cameraID
        Task { await restart(rebuild: false) }
    }

    /// The preview's size changed (a fold, unfold or rotation): keep it upright, and bring the
    /// session back if the change left it stopped.
    private func layoutChanged() {
        updatePreviewRotation()
        guard status == .running else { return }
        let camera = camera
        Task {
            if await !camera.isRunning { await restart(rebuild: true) }
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        let session = camera.session
        let rebuild: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.restartLater(rebuild: true) }
        }
        observers = [
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartLater(rebuild: false) }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main, using: rebuild),
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main, using: rebuild),
        ]
    }

    private func restartLater(rebuild: Bool) {
        Task { await restart(rebuild: rebuild) }
    }

    // MARK: - Rotation

    private func makeRotationCoordinator(for cameraID: String) {
        guard let device = AVCaptureDevice(uniqueID: cameraID), let layer = previewView?.previewLayer else { return }
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
    }

    private func updatePreviewRotation() {
        guard let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview,
              let connection = previewView?.previewLayer.connection,
              connection.isVideoRotationAngleSupported(angle)
        else { return }
        connection.videoRotationAngle = angle
    }
}

/// A view whose layer is the camera preview; reports layout changes (rotation, fold, unfold).
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // The layer class above guarantees the type.
        layer as! AVCaptureVideoPreviewLayer
    }

    var onLayout: (() -> Void)?
    private var lastSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onLayout?()
    }
}

/// The live camera preview for package scanning.
struct PackageCameraPreview: UIViewRepresentable {
    let controller: PackageCameraController

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        controller.attach(view)
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {}
}
