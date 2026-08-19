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
    
    // Simulator testing
    #if targetEnvironment(simulator)
    var testImageURL: URL? {
        didSet {
            if isRunning, let url = testImageURL {
                loadTestImage(from: url)
            }
        }
    }
    #endif

    override init() {
        super.init()
    }

    deinit {}

    func start() {
        guard !isRunning else { return }
        discoveryTimer?.invalidate()
        
        #if targetEnvironment(simulator)
        // Simulator mode: use mock data
        startSimulatorMode()
        #else
        status = .searching
        attemptDiscoveryAndStart()
        if !isRunning {
            // Poll every 2 seconds until a device appears or stop() is called
            discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.attemptDiscoveryAndStart()
            }
        }
        #endif
    }

    func stop() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        
        #if targetEnvironment(simulator)
        simulatorTimer?.invalidate()
        simulatorTimer = nil
        #endif
        
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
        #if targetEnvironment(simulator)
        // Simulator doesn't support AVCapture devices
        return nil
        #else
        // On visionOS, use the default video device if available. This will represent
        // an attached Continuity Camera source when present.
        return AVCaptureDevice.default(for: .video)
        #endif
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
    
    // MARK: - Simulator Mode
    
    #if targetEnvironment(simulator)
    private var simulatorTimer: Timer?
    
    private func startSimulatorMode() {
        isRunning = true
        status = .connected(deviceName: "Simulator Test Camera")
        
        // Generate a test image
        let testImage = generateTestImage()
        latestImage = testImage
        
        // Simulate camera frames at 30fps
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                // Generate slightly different images to simulate camera feed
                let img = self.generateTestImage()
                self.latestImage = img
                
                // Throttled detection forwarding
                let now = Date()
                if self.detectionEnabled && now.timeIntervalSince(self.lastDetectionTime) >= self.detectionInterval {
                    if self.shouldProcess(img) {
                        self.lastDetectionTime = now
                        await self.onFrameForDetection?(img)
                    }
                }
            }
        }
    }
    
    private func generateTestImage() -> UIImage {
        let size = CGSize(width: 1920, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Background gradient
            let colors = [UIColor.systemBlue.withAlphaComponent(0.3), UIColor.systemPurple.withAlphaComponent(0.2)]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors.map { $0.cgColor } as CFArray,
                                      locations: [0.0, 1.0])!
            context.cgContext.drawLinearGradient(gradient,
                                                  start: .zero,
                                                  end: CGPoint(x: size.width, y: size.height),
                                                  options: [])
            
            // Add some text to make frames visually different
            let timeString = "Simulator Feed\n\(Date().formatted(date: .omitted, time: .standard))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            
            let textSize = timeString.size(withAttributes: attributes)
            let textRect = CGRect(x: (size.width - textSize.width) / 2,
                                  y: (size.height - textSize.height) / 2,
                                  width: textSize.width,
                                  height: textSize.height)
            
            timeString.draw(in: textRect, withAttributes: attributes)
            
            // Add a "fake" surgical tray overlay for testing
            context.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.8).cgColor)
            context.cgContext.setLineWidth(4)
            let trayRect = CGRect(x: size.width * 0.2, y: size.height * 0.3,
                                  width: size.width * 0.6, height: size.height * 0.4)
            context.cgContext.stroke(trayRect)
            
            // Add "tools" rectangles
            for i in 0..<5 {
                let x = size.width * 0.25 + CGFloat(i) * size.width * 0.1
                let toolRect = CGRect(x: x, y: size.height * 0.45, width: 60, height: 200)
                context.cgContext.setFillColor(UIColor.systemGray.withAlphaComponent(0.6).cgColor)
                context.cgContext.fill(toolRect)
            }
        }
    }
    
    private func loadTestImage(from url: URL) {
        Task { @MainActor in
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                status = .error("Failed to load test image")
                return
            }
            latestImage = image
            status = .connected(deviceName: "Test Image: \(url.lastPathComponent)")
            
            // Trigger detection if enabled
            if detectionEnabled {
                await onFrameForDetection?(image)
            }
        }
    }
    #endif

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
