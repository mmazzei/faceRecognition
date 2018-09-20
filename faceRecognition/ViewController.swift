//
//  ViewController.swift
//  faceRecognition
//
//  Created by Matías Mazzei on 20/09/2018.
//  Copyright © 2018 Ballast Lane. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet weak var cameraPreview: UIView!
    @IBOutlet weak var facesFramingView: ObjectRecognitionView!
    @IBOutlet weak var facesIndicator: UIView!
    @IBOutlet weak var messageDisplay: UILabel!

    private var cameraRecorder: CameraRecorder!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        cameraRecorder = CameraRecorder(previewView: cameraPreview)
        cameraRecorder.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        cameraRecorder.startRunning()
        super.viewDidAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraRecorder.endRecording()
    }
}

extension ViewController: CameraRecorderDelegate {
    func cameraRecorder(_: CameraRecorder, detectedFacesAt bounds: [CGRect]) {
        DispatchQueue.main.async {[unowned self] in
            self.facesFramingView.objectFrames = bounds

            switch bounds.count {
            case 0:
                self.facesIndicator.backgroundColor = .white
            case 1:
                self.facesIndicator.backgroundColor = .green
            default:
                self.facesIndicator.backgroundColor = .red
            }
        }
    }

    func cameraRecorder(_: CameraRecorder, didChangeState state: CameraRecorder.State) {
        DispatchQueue.main.async {
            switch state {
            case .failed(error: let error):
                self.messageDisplay.text = "Error while configuring the camera: \(error.localizedDescription)"
                self.messageDisplay.isHidden = false
            case .unauthorized:
                self.messageDisplay.text = "Please authorize this app for camera access and try again."
                self.messageDisplay.isHidden = false
            case .recording:
                self.messageDisplay.isHidden = true
            default:
                self.messageDisplay.text = "\(state)"
                self.messageDisplay.isHidden = false
            }
        }
    }
}
