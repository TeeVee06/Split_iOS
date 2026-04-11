//
//  QRCodeScannerView.swift
//  Split
//
//  A reusable QR code scanner view using AVFoundation.
//  Emits the first decoded QR string via `onCodeScanned`.
//

import SwiftUI
import AVFoundation

struct QRCodeScannerView: UIViewRepresentable {
    let onCodeScanned: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black

        let coordinator = context.coordinator

        // Handle camera permission
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authStatus {
        case .authorized:
            coordinator.configureSessionIfNeeded(in: view)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        coordinator.configureSessionIfNeeded(in: view)
                    } else {
                        coordinator.reportError("Camera access was denied.")
                    }
                }
            }

        case .denied, .restricted:
            coordinator.reportError("Camera access is restricted or denied. Enable it in Settings to scan QR codes.")

        @unknown default:
            coordinator.reportError("Unknown camera authorization status.")
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Keep the preview layer sized correctly when layout changes
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopSession()
        coordinator.previewLayer?.removeFromSuperlayer()
        coordinator.previewLayer = nil
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCodeScanned: (String) -> Void

        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var didScanCode = false
        let sessionQueue = DispatchQueue(label: "split.qr-code-scanner.session", qos: .userInitiated)

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didScanCode,
                  let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  first.type == .qr,
                  let value = first.stringValue,
                  !value.isEmpty else {
                return
            }

            didScanCode = true
            stopSession()
            onCodeScanned(value)
        }

        func reportError(_ message: String) {
            // For now we just log; if you want, we can later
            // add a binding to surface camera errors into SwiftUI.
            print("QR Scanner error:", message)
        }

        func configureSessionIfNeeded(in view: UIView) {
            sessionQueue.async { [weak self, weak view] in
                guard let self else { return }

                if let session = self.session {
                    if !session.isRunning {
                        session.startRunning()
                    }
                    return
                }

                let session = AVCaptureSession()

                guard let device = AVCaptureDevice.default(for: .video) else {
                    self.reportError("No camera available on this device.")
                    return
                }

                guard let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    self.reportError("Unable to access camera input.")
                    return
                }

                session.beginConfiguration()
                session.addInput(input)

                let output = AVCaptureMetadataOutput()
                guard session.canAddOutput(output) else {
                    session.commitConfiguration()
                    self.reportError("Unable to read camera output.")
                    return
                }

                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                output.metadataObjectTypes = [.qr]
                session.commitConfiguration()

                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.videoGravity = .resizeAspectFill

                self.session = session

                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    previewLayer.frame = view.bounds
                    view.layer.addSublayer(previewLayer)
                    self.previewLayer = previewLayer
                }

                session.startRunning()
            }
        }

        func stopSession() {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if let session = self.session, session.isRunning {
                    session.stopRunning()
                }
                self.session = nil
            }
        }
    }
}
