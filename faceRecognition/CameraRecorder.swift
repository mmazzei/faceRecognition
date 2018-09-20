//
//  CameraRecorder.swift
//  faceRecognition
//
//  Created by Matías Mazzei on 20/09/2018.
//  Copyright © 2018 Ballast Lane. All rights reserved.
//

import AVFoundation
import UIKit

protocol CameraRecorderDelegate: class {
    func cameraRecorder(_: CameraRecorder, detectedFacesAt bounds: [CGRect])
    func cameraRecorder(_: CameraRecorder, didChangeState state: CameraRecorder.State)
}

// MARK: - Owned enums
extension CameraRecorder {
    enum CameraControllerError: Swift.Error {
        case captureSessionAlreadyRunning
        case captureSessionIsMissing
        case inputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case noAudioAvailable
        case unknown
    }

    enum SessionSetupResult: Error {
        case success
        case notAuthorized
        case configurationFailed
        case undefinedError
    }

    enum State: Equatable {
        case created
        case initialized
        case unauthorized
        case authorized
        case preparing
        case recording(facesDetected: Int)
        case stopping
        case stopped
        case failed(error: Error)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.created, .created): return true
            case (.initialized, .initialized): return true
            case (.unauthorized, .unauthorized): return true
            case (.authorized, .authorized): return true
            case (.preparing, .preparing): return true
            case let (.recording(lhsFacesDetected), .recording(rhsFacesDetected)):
                return lhsFacesDetected == rhsFacesDetected
            case (.stopping, .stopping): return true
            case (.stopped, .stopped): return true
            case (.failed, .failed): return true
            default: return false
            }
        }
    }
}

class CameraRecorder: NSObject {

    // MARK: Internal Properties
    fileprivate let sessionQueue = DispatchQueue(label: "session queue", attributes: [], target: nil)

    // MARK: private Properties
    fileprivate let session = AVCaptureSession()
    fileprivate let captureOutput = AVCaptureVideoDataOutput()
    fileprivate var previewLayer: AVCaptureVideoPreviewLayer!
    fileprivate var videoDeviceInput: AVCaptureDeviceInput!
    fileprivate var captureAudio: AVCaptureDevice?
    private weak var previewView: UIView!

    // MARK: Public properties
    weak var delegate: CameraRecorderDelegate?
    private(set) var state: State = .created {
        didSet { delegate?.cameraRecorder(self, didChangeState: state) }
    }

    // MARK: Initialization functions
    /// Transicion: created => initialized
    init(previewView: UIView) {
        self.previewView = previewView
        super.init()
        state = .initialized
    }

    // MARK: Control recorder

    /// Transition:
    /// - not authorized => checks auth
    /// - authorized => asks for camera permission
    func startRunning() {
        switch state {
        case .initialized, .unauthorized:
            checkAuthorization()
        case .authorized:
            requestCameraPermission()
        case .created, .preparing, .recording, .stopping, .stopped, .failed:
            print("⚠️ Trying to reuse a CameraRecorder in an invalid state: \(state)")
            return
        }
    }

    /// Transition: any => stopping
    func endRecording() {
        session.stopRunning()
        state = .stopped
    }

    // MARK: Internal Helpers

    // MARK: Session Management
    /// Transition:
    /// - initialized => unauthorized
    /// - initialized => authorized
    private func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .authorized
            requestCameraPermission()

        case .notDetermined: // The user has not yet been asked for camera access.
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.checkAuthorization()
                }
            }

        case .denied: // The user has previously denied access.
            state = .unauthorized
            return

        case .restricted: // The user can't grant access due to restrictions.
            state = .unauthorized
            return
        }
    }

    /// Transition: authorized => preparing
    private func requestCameraPermission() {
        switch state {
        case .authorized:
            DispatchQueue.main.async { [unowned self] in
                self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
                self.previewLayer.frame = self.previewView.bounds
                self.previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
                self.previewView.layer.addSublayer(self.previewLayer)
                self.session.startRunning()
                self.state = .preparing

                self.sessionQueue.async { [unowned self] in
                    self.configureSession()
                }
            }
        default:
            break
        }
    }

    /// Transition:
    ///  - preparing => recording
    ///  - preparing => failed
    private func configureSession() {
        guard case .preparing = state else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Add video input.
        do {
            let defaultVideoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .front)
            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice!)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                print("📸 CameraRecorder - Could not add video device input to the session")
                state = .failed(error: SessionSetupResult.configurationFailed)
                return
            }
        } catch {
            print("📸 CameraRecorder - Could not create video device input: \(error)")
            state = .failed(error: SessionSetupResult.configurationFailed)
            return
        }

        startMetaSession()
        state = .recording(facesDetected: -1)
    }

    /// Transition: any => failed (in case of errors)
    private func startMetaSession() {
        let metadataOutput = AVCaptureMetadataOutput()
        metadataOutput.setMetadataObjectsDelegate(self, queue: self.sessionQueue)
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
        }
        if metadataOutput.availableMetadataObjectTypes.contains(where: { return $0 == AVMetadataObject.ObjectType.face }) {
            metadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.face]
        } else {
            state = .failed(error: SessionSetupResult.undefinedError)
        }
    }
}

extension CameraRecorder: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard case .recording = state else { return }

        var faceObjects = [AVMetadataFaceObject]()

        _ = metadataObjects.map { metadataObject in
            guard let metaFaceObject = metadataObject as? AVMetadataFaceObject,
                metaFaceObject.type == AVMetadataObject.ObjectType.face,
                let object = previewLayer?.transformedMetadataObject(for: metaFaceObject) as? AVMetadataFaceObject,
                object.bounds != CGRect.zero,
                let layer = previewLayer else { return }
            if layer.bounds.contains(object.bounds) {
                faceObjects.append(object)
            }
        }
        state = .recording(facesDetected: faceObjects.count)

        let faceBounds = faceObjects.map { $0.bounds }
        delegate?.cameraRecorder(self, detectedFacesAt: faceBounds)
    }

    /// Transition: recording => recording(face detected updated)
    func captureOutput(_ captureOutput: AVCaptureOutput!,
                       didOutputMetadataObjects metadataObjects: [Any]!,
                       from connection: AVCaptureConnection!) {
        guard case .recording = state else { return }

        var faceObjects = [AVMetadataFaceObject]()

        _ = metadataObjects.map { metadataObject in
            guard let metaFaceObject = metadataObject as? AVMetadataFaceObject,
                metaFaceObject.type == AVMetadataObject.ObjectType.face,
                let object = previewLayer?.transformedMetadataObject(for: metaFaceObject) as? AVMetadataFaceObject,
                object.bounds != CGRect.zero,
                let layer = previewLayer else { return }
            if layer.bounds.intersects(object.bounds) {
                faceObjects.append(object)
            }
        }
        state = .recording(facesDetected: faceObjects.count)

        let faceBounds = faceObjects.map { $0.bounds }
        delegate?.cameraRecorder(self, detectedFacesAt: faceBounds)
    }
}
