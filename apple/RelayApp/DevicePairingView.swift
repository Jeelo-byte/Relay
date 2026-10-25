import RelayKit
import SwiftUI
import CoreImage.CIFilterBuiltins
import AVFoundation
#if os(iOS)
import VisionKit
import UIKit
#else
import AppKit
import Vision
#endif

struct PairDeviceView: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dismiss) private var dismiss
  @State private var code: DevicePairingCode?
  @State private var status: DevicePairingStatus?
  @State private var busy = false
  @State private var issue: String?
  @State private var notice: String?
  @State private var approved = false
  @State private var generation = UUID()
  var body: some View {
    NavigationStack {
      SettingsPage(title: "Pair a Device", subtitle: "Open Relay on your other device and choose Scan Pairing Code.", symbol: "qrcode") {
        SettingsCard {
          if let code {
            PairingQR(link: code.link)
            Text("Check Code: \(code.checkCode)").font(.title3.monospaced().bold()).textSelection(.enabled)
            Text("This code expires after five minutes. Keep both devices open.").foregroundStyle(RelayTheme.muted)
            if ["localhost", "127.0.0.1", "::1"].contains(code.server.host ?? "") {
              Text("To pair an iPhone, first connect this account using your Mac’s reachable HTTPS address. A localhost code only works on this Mac.").foregroundStyle(RelayTheme.warning)
            }
            if let status, let target = status.target_device_id {
              Text("\(status.deviceLabel) Wants to Pair").font(.headline)
              Text("Compare the check code on both devices. Approving gives this device access to your encrypted agreements and recaps.")
              Button(approved ? "Approved — Waiting for Device" : "Approve \(status.deviceLabel)") { approve(target) }
                .buttonStyle(.borderedProminent).disabled(busy || approved)
            } else { Label("Waiting for your other device to scan…", systemImage: "iphone") }
            DisclosureGroup("Can’t Scan?") {
              Text("Paste this private link into Relay on your other device.").font(.caption)
              Text(code.link).font(.caption.monospaced()).textSelection(.enabled)
              ShareLink("Share Private Pairing Link", item: code.link)
            }
            Button("Cancel Pairing", role: .cancel) { cancel() }
          } else {
            Button(busy ? "Creating Code…" : "Show Pairing Code", action: create).buttonStyle(.borderedProminent).disabled(busy || store.locked || store.session == nil)
          }
          if let notice { Text(notice).accessibilityAddTraits(.updatesFrequently) }
          if let issue { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(RelayTheme.danger) }
        }
      }.navigationTitle("Pair a Device").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
    .task(id: code?.id) {
      guard let code, let session = store.session else { return }
      let client = APIClient(baseURL: session.baseURL, token: session.token)
      while !Task.isCancelled && !store.locked && store.session?.token == session.token {
        do {
          let next = try await client.pairingStatus(code.id)
          guard !Task.isCancelled, self.code?.id == code.id else { return }
          status = next
          try await Task.sleep(for: .seconds(2))
        } catch is CancellationError { return }
        catch {
          guard !Task.isCancelled, self.code?.id == code.id else { return }
          if approved, (error as? APIError)?.status == 410 { notice = "Pairing has closed. Check your other device to continue." }
          else { issue = error.localizedDescription }
          cancel(); return
        }
      }
    }
    .onChange(of: store.locked) { _, locked in if locked { cancel(); dismiss() } }
    .onDisappear { cancel() }
    #if os(macOS)
    .frame(minWidth: 480, idealWidth: 560, minHeight: 620)
    #endif
  }
  private func create() {
    guard let session = store.session, !store.locked else { return }
    let run = UUID(); generation = run; busy = true; issue = nil; notice = nil; approved = false
    let next = DevicePairingCode(server: session.baseURL)
    Task {
      let client = APIClient(baseURL: session.baseURL, token: session.token)
      do {
        let result = try await client.createPairing(session: session, code: next)
        guard generation == run, !store.locked, store.session?.token == session.token else { try? await client.cancelPairing(next.id); return }
        status = result; code = next
      } catch { if generation == run { issue = error.localizedDescription } }
      if generation == run { busy = false }
    }
  }
  private func cancel() {
    generation = UUID()
    if let code, let session = store.session {
      Task { try? await APIClient(baseURL: session.baseURL, token: session.token).cancelPairing(code.id) }
    }
    code = nil; status = nil; busy = false
  }
  private func approve(_ target: UUID) {
    guard let code, let session = store.session, !store.locked else { return }
    let run = generation; busy = true
    Task {
      do {
        try await APIClient(baseURL: session.baseURL, token: session.token).approvePairing(code.id, device: target)
        if run == generation && !store.locked { approved = true }
      } catch { if run == generation { issue = error.localizedDescription } }
      if run == generation { busy = false }
    }
  }
}

struct PairingQR: View {
  let link: String
  var body: some View {
    let filter = CIFilter.qrCodeGenerator()
    let _ = filter.setValue(Data(link.utf8), forKey: "inputMessage")
    let _ = filter.setValue("M", forKey: "inputCorrectionLevel")
    if let output = filter.outputImage,
      let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) {
      Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
        .padding(24).background(.white).clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 300).accessibilityLabel("Private Relay pairing code. Scan with your other device.")
    }
  }
}

struct JoinDeviceView: View {
  @EnvironmentObject private var store: RelayStore
  @State private var link = ""
  @State private var scanner = false
  @State private var pending: DevicePairingRequest?
  @State private var busy = false
  @State private var issue: String?
  @State private var generation = UUID()
  private var parsed: DevicePairingCode? { try? DevicePairingCode(link: link) }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Label("Pair This Device", systemImage: "qrcode.viewfinder").font(.title2.bold())
      Text("On your signed-in Mac, iPhone, or browser, open Settings → Devices → Pair a Device.").foregroundStyle(RelayTheme.muted)
      if let pending {
        ProgressView("Waiting for approval…")
        Text("Check Code: \(pending.code.checkCode)").font(.title3.monospaced().bold())
        Text("Compare this code, then approve this device on your other device.")
        Button("Cancel Pairing") { cancel() }
      } else {
        #if os(iOS)
        if DataScannerViewController.isSupported {
          Button("Scan Pairing Code") {
            Task {
              let allowed = await AVCaptureDevice.requestAccess(for: .video)
              if allowed && DataScannerViewController.isAvailable { scanner = true }
              else { issue = "Camera unavailable. Allow camera access in Settings, or paste your private pairing link below." }
            }
          }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        #else
        Button("Scan Pairing Code") {
          Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            if allowed { scanner = true }
            else { issue = "Allow camera access in System Settings, or paste your private pairing link below." }
          }
        }.buttonStyle(.borderedProminent).controlSize(.large)
        #endif
        TextField("Paste a Private Pairing Link", text: $link, axis: .vertical).textFieldStyle(.roundedBorder).autocorrectionDisabled()
        if let parsed {
          Text("Connect to \(parsed.server.absoluteString)").font(.caption).textSelection(.enabled)
          Text("Check Code: \(parsed.checkCode)").font(.headline.monospaced())
        }
        Button(busy ? "Connecting…" : "Pair This Device", action: join).buttonStyle(.borderedProminent).disabled(busy || parsed == nil)
        Text("New to Relay? Choose Create Account below to set up your first device.").font(.caption).foregroundStyle(RelayTheme.muted)
      }
      if let issue { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(RelayTheme.danger) }
    }
    #if os(iOS)
    .sheet(isPresented: $scanner) {
      NavigationStack {
        PairingScanner(onScan: { value in
          scanner = false
          if (try? DevicePairingCode(link: value)) != nil { link = value; issue = nil }
          else { issue = DevicePairingCode.invalidCode.localizedDescription }
        }, onError: { message in scanner = false; issue = message })
          .navigationTitle("Scan Pairing Code").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanner = false } } }
      }
    }
    #endif
    #if os(macOS)
    .sheet(isPresented: $scanner) {
      VStack(spacing: 20) {
        Text("Scan Pairing Code").font(.title2.bold())
        MacPairingScanner(onScan: { value in
          scanner = false
          if (try? DevicePairingCode(link: value)) != nil { link = value; issue = nil }
          else { issue = DevicePairingCode.invalidCode.localizedDescription }
        }, onError: { message in scanner = false; issue = message }).frame(minWidth: 480, minHeight: 320)
        Button("Cancel") { scanner = false }
      }.padding(24)
    }
    #endif
    .task(id: pending?.code.id) {
      guard let pending else { return }
      let client = APIClient(baseURL: pending.code.server)
      while !Task.isCancelled {
        do {
          if let session = try await client.claimPairing(pending) {
            guard !Task.isCancelled, self.pending?.code.id == pending.code.id else {
              _ = try? await APIClient(baseURL: session.baseURL, token: session.token).request("sessions/current", method: "DELETE"); return
            }
            do { try store.connect(session) }
            catch {
              _ = try? await APIClient(baseURL: session.baseURL, token: session.token).request("sessions/current", method: "DELETE")
              throw error
            }
            self.pending = nil; return
          }
          try await Task.sleep(for: .seconds(2))
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { issue = error.localizedDescription; cancel() }; return }
      }
    }
    .onDisappear { cancel() }
  }
  private func join() {
    guard let parsed else { issue = DevicePairingCode.invalidCode.localizedDescription; return }
    let run = UUID(); generation = run; busy = true; issue = nil
    Task {
      let client = APIClient(baseURL: parsed.server)
      do {
        let request = try await client.joinPairing(parsed)
        guard run == generation else { try? await client.cancelPairingRequest(request); return }
        pending = request; link = ""
      } catch { if run == generation { issue = error.localizedDescription } }
      if run == generation { busy = false }
    }
  }
  private func cancel() {
    generation = UUID(); busy = false; link = ""
    if let pending { Task { try? await APIClient(baseURL: pending.code.server).cancelPairingRequest(pending) } }
    pending = nil
  }
}

#if os(iOS)
private struct PairingScanner: UIViewControllerRepresentable {
  var onScan: (String) -> Void
  var onError: (String) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onError: onError) }
  func makeUIViewController(context: Context) -> DataScannerViewController {
    let controller = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
      recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
    controller.delegate = context.coordinator
    do { try controller.startScanning() } catch { DispatchQueue.main.async { context.coordinator.onError("The camera could not start. Try again or paste your pairing link.") } }
    return controller
  }
  func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
  static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    let onScan: (String) -> Void
    let onError: (String) -> Void
    var scanned = false
    init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) { self.onScan = onScan; self.onError = onError }
    func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
      onError("Camera unavailable. Try again or paste your private pairing link.")
    }
    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
      for item in addedItems {
        if case .barcode(let barcode) = item, let text = barcode.payloadStringValue, !scanned {
          scanned = true; dataScanner.stopScanning(); onScan(text); return
        }
      }
    }
  }
}
#endif

#if os(macOS)
private struct MacPairingScanner: NSViewControllerRepresentable {
  let onScan: (String) -> Void
  let onError: (String) -> Void
  func makeNSViewController(context: Context) -> MacQRController { MacQRController(onScan: onScan, onError: onError) }
  func updateNSViewController(_ controller: MacQRController, context: Context) {}
  static func dismantleNSViewController(_ controller: MacQRController, coordinator: ()) { controller.stop() }
}
private final class MacQRController: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
  private let capture = AVCaptureSession()
  private let queue = DispatchQueue(label: "app.relay.pairing-camera")
  private var preview: AVCaptureVideoPreviewLayer?
  private var finished = false
  private var stopped = false
  private let onScan: (String) -> Void
  private let onError: (String) -> Void
  init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
    self.onScan = onScan; self.onError = onError; super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func loadView() { view = NSView(); view.wantsLayer = true }
  override func viewDidLoad() {
    super.viewDidLoad()
    let layer = AVCaptureVideoPreviewLayer(session: capture); layer.videoGravity = .resizeAspectFill
    view.layer?.addSublayer(layer); preview = layer
    queue.async { [self] in
      guard !stopped else { return }
      do {
        guard let camera = AVCaptureDevice.default(for: .video) else { throw DevicePairingCode.invalidCode }
        let input = try AVCaptureDeviceInput(device: camera)
        let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        capture.beginConfiguration()
        guard capture.canAddInput(input), capture.canAddOutput(output) else {
          capture.commitConfiguration(); throw DevicePairingCode.invalidCode
        }
        capture.addInput(input); capture.addOutput(output); capture.commitConfiguration(); capture.startRunning()
      } catch { DispatchQueue.main.async { self.onError("Camera unavailable. Allow camera access in System Settings, or paste your private pairing link.") } }
    }
  }
  override func viewDidLayout() { super.viewDidLayout(); preview?.frame = view.bounds }
  func stop() { queue.async { self.stopped = true; self.capture.stopRunning() } }
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard !finished, !stopped, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
    try? VNImageRequestHandler(cvPixelBuffer: pixels).perform([request])
    if let text = request.results?.first?.payloadStringValue {
      finished = true
      DispatchQueue.main.async { self.onScan(text) }
    }
  }
}
#endif
