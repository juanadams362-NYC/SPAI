import Foundation
import AVFoundation
import SwiftUI
import CoreImage
import CoreGraphics

@MainActor
@Observable
final class ContinuityCameraService: NSObject {
    enum Status: Equatable {
        case disconnected
        case searching
        case connected(deviceName: String)
        case error(String)

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .searching:    return "Searching…"
            case .connected(let name): return "Connected: \(name)"
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var color: Color {
            switch self {
            case .connected:   return SPAIColor.safe
            case .searching:   return SPAIColor.secondary
            case .disconnected:return .white.opacity(0.7)
            case .error:       return SPAIColor.warning
            }
        }
    }

    // Published state
    private(set) var status: Status = .disconnected
    private(set) var isRunning: Bool = false
    private(set) var latestImage: UIImage?

    // Capture
    private var session: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var input: AVCaptureDeviceInput?
    private var discoveryTimer: Timer?

    // Frame conversion
    private let ciContext = CIContext()
    private let sampleQueue = DispatchQueue(label: "cc.sample.queue")

    // Detection bridging
    var detectionEnabled: Bool = false
    var detectionInterval: TimeInterval = 1.0
    private var lastDetectionTime: Date = .distantPast
    var onFrameForDetection: ((UIImage) async -> Void)?
    private var lastFingerprint: [UInt8]?

    override init() {
        super.init()
    }

    deinit {}

    func start() {
        guard !isRunning else { return }
        discoveryTimer?.invalidate()
        status = .searching
        attemptDiscoveryAndStart()
        if !isRunning {
            // Poll every 2 seconds until a device appears or stop() is called
            discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.attemptDiscoveryAndStart()
            }
        }
    }

    func stop() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        session?.stopRunning()
        session = nil
        videoOutput = nil
        input = nil
        isRunning = false
        status = .disconnected
        latestImage = nil
    }

    // MARK: - Discovery

    private func discoverContinuityCamera() -> AVCaptureDevice? {
        // On visionOS, use the default video device if available. This will represent
        // an attached Continuity Camera source when present.
        return AVCaptureDevice.default(for: .video)
    }

    private func attemptDiscoveryAndStart() {
        guard !isRunning else { return }
        if let device = discoverContinuityCamera() {
            discoveryTimer?.invalidate()
            discoveryTimer = nil
            configureSession(with: device)
        } else {
            status = .searching
        }
    }

    // MARK: - Session

    private func configureSession(with device: AVCaptureDevice) {
        let session = AVCaptureSession()
        session.beginConfiguration()

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            self.input = input
        } catch {
            status = .error("Input failed: \(error.localizedDescription)")
            session.commitConfiguration()
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(output) { session.addOutput(output) }
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        self.videoOutput = output

        session.commitConfiguration()
        self.session = session

        session.startRunning()
        isRunning = true
        status = .connected(deviceName: device.localizedName)
    }

    // MARK: - Frame handling

    private func handle(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            let ui = UIImage(cgImage: cgImage)
            Task { @MainActor in
                self.latestImage = ui
                // Throttled detection forwarding
                let now = Date()
                if self.detectionEnabled && now.timeIntervalSince(self.lastDetectionTime) >= self.detectionInterval {
                    if self.shouldProcess(ui) {
                        self.lastDetectionTime = now
                        await self.onFrameForDetection?(ui)
                    }
                }
            }
        }
    }

    // MARK: - Frame change filtering
    private func shouldProcess(_ image: UIImage) -> Bool {
        guard let fingerprint = fingerprint(for: image) else { return true }
        defer { lastFingerprint = fingerprint }
        guard let last = lastFingerprint, last.count == fingerprint.count else { return true }
        let totalDelta = zip(last, fingerprint).reduce(0) { sum, pair in
            sum + abs(Int(pair.0) - Int(pair.1))
        }
        let avg = Double(totalDelta) / Double(fingerprint.count)
        return avg >= 4.0
    }

    private func fingerprint(for image: UIImage) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}

extension ContinuityCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        handle(sampleBuffer: sampleBuffer)
    }
}
