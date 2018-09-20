//
//  ObjectRecognitionView.swift
//  faceRecognition
//
//  Created by Matías Mazzei on 20/09/2018.
//  Copyright © 2018 Ballast Lane. All rights reserved.
//

import UIKit
import AVKit

/// A view which draws the given rectangles (it is supposed to be used on top of another view with
/// a video preview layer, and the rectangles being the frames of recognized objects).
class ObjectRecognitionView: UIView {
    var objectFrames: [CGRect] = [] {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        customInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        customInit()
    }

    private func customInit() {
        backgroundColor = .clear
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        for objectFrame in objectFrames {
            draw(rectangle: objectFrame)
        }
    }

    private func draw(rectangle: CGRect) {
        let path = UIBezierPath(rect: rectangle)
        UIColor.red.setStroke()
        path.lineWidth = 3.0
        path.stroke()
    }
}
