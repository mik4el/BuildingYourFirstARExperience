/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import UIKit
import SceneKit
import ARKit
import AudioToolbox.AudioServices
import AVFoundation.AVCaptureDevice
import CoreMotion
import AVFoundation

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
	// MARK: - IBOutlets

    @IBOutlet weak var sessionInfoView: UIView!
	@IBOutlet weak var sessionInfoLabel: UILabel!
	@IBOutlet weak var sceneView: ARSCNView!

    @IBOutlet weak var rotZ: UILabel!
    @IBOutlet weak var distance: UILabel!

	// MARK: - View Life Cycle
	let manager = CMMotionManager()
    var cube: SCNBox = SCNBox()
    var cubeNode: SCNNode = SCNNode()
    
    // states
    var plane_found = false
    var within_distance = false
    var angle_correct = false
    var capture_complete = false
    var have_turned_on_flash = false

    override func viewDidLoad() {
        super.viewDidLoad()

        manager.gyroUpdateInterval = 0.1
        manager.accelerometerUpdateInterval = 0.1
        
        manager.startGyroUpdates()
        manager.startAccelerometerUpdates()
        
        let epsilon = 0.02
        let desired_rotation_z = -0.5 // 45 deg, range -1.0 to 1.0 for full rotation
        var time_started_desired_rotation: UInt64 = 0
        var time_started_capture_complete: UInt64 = 0
        
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 0.01
            manager.startDeviceMotionUpdates(to: OperationQueue.main) {
                [weak self] data, error in
                self?.rotZ.text = String(format: "RotZ: -")
                self?.rotZ.textColor = .white
                // Rewrite as explicit state machine
                if (self?.within_distance)! {
                    self?.rotZ.text = String(format: "RotZ (~45 deg): %.1f deg", -data!.gravity.z*90.0)
                    self?.rotZ.textColor = .red
                    if (self?.capture_complete)! || !(self?.plane_found)! {
                        if UInt64(NSDate().timeIntervalSince1970 * 1000.0) > time_started_capture_complete + 2000 {
                            self?.capture_complete = false
                        }
                    } else {
                        if data!.gravity.z < desired_rotation_z - epsilon || data!.gravity.z > desired_rotation_z + epsilon {
                            // Outside desired rotation
                            self?.rotZ.textColor = .red
                            time_started_desired_rotation = 0
                        }
                        else {
                            // Within desired rotation
                            self?.rotZ.textColor = .green
                            AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
                            if (time_started_desired_rotation==0) {
                                time_started_desired_rotation = UInt64(NSDate().timeIntervalSince1970 * 1000.0)
                            }
                            else {
                                if UInt64(NSDate().timeIntervalSince1970 * 1000.0) > time_started_desired_rotation + 1000 {
                                    // turn on light
                                    if !(self?.have_turned_on_flash)! {
                                        self?.turnOnFlash()
                                        self?.have_turned_on_flash = true
                                    }
                                }
                                if UInt64(NSDate().timeIntervalSince1970 * 1000.0) > time_started_desired_rotation + 2000 {
                                    // play capture sound and turn off flash
                                    self?.capture_complete = true
                                    time_started_capture_complete = UInt64(NSDate().timeIntervalSince1970 * 1000.0)
                                    self?.turnOffFlash()
                                    self?.have_turned_on_flash = false
                                    self?.playSound()
                                    time_started_desired_rotation = 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    var player: AVAudioPlayer?
    
    func playSound() {
        // from https://stackoverflow.com/questions/32036146/how-to-play-a-sound-using-swift
        guard let url = Bundle.main.url(forResource: "camera-shutter", withExtension: "mp3") else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            try AVAudioSession.sharedInstance().setActive(true)

            
            /* The following line is required for the player to work on iOS 11. Change the file type accordingly*/
            player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.mp3.rawValue)
            
            /* iOS 10 and earlier require the following line:
             player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileTypeMPEGLayer3) */
            
            guard let player = player else { return }
            
            player.play()
        } catch let error {
            print(error.localizedDescription)
        }
    }
    
    /// - Tag: StartARSession
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard ARWorldTrackingConfiguration.isSupported else {
            fatalError("""
                ARKit is not available on this device. For apps that require ARKit
                for core functionality, use the `arkit` key in the key in the
                `UIRequiredDeviceCapabilities` section of the Info.plist to prevent
                the app from installing. (If the app can't be installed, this error
                can't be triggered in a production scenario.)
                In apps where AR is an additive feature, use `isSupported` to
                determine whether to show UI for launching AR experiences.
            """) // For details, see https://developer.apple.com/documentation/arkit
        }

        /*
         Start the view's AR session with a configuration that uses the rear camera,
         device position and orientation tracking, and plane detection.
        */
        let configuration = ARWorldTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)

        // Set a delegate to track the number of plane anchors for providing UI feedback.
        sceneView.session.delegate = self
       
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
        //sceneView.debugOptions = ARSCNDebugOptions.showFeaturePoints
        
        /*
         Prevent the screen from being dimmed after a while as users will likely
         have long periods of interaction without touching the screen or buttons.
        */
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Show debug UI to view performance metrics (e.g. frames per second).
        sceneView.showsStatistics = false
        
    }

    func turnOnFlash() {
        let device = AVCaptureDevice.default(for: AVMediaType.video)
        do {
            try device!.lockForConfiguration()
            device!.torchMode = AVCaptureDevice.TorchMode.on
            device!.unlockForConfiguration()
        } catch {
            print(error)
        }
    }
    
    func turnOffFlash() {
        let device = AVCaptureDevice.default(for: AVMediaType.video)
        do {
            try device!.lockForConfiguration()
            device!.torchMode = AVCaptureDevice.TorchMode.off
            device!.unlockForConfiguration()
        } catch {
            print(error)
        }
    }
    
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		
		// Pause the view's AR session.
		sceneView.session.pause()
	}
	
	// MARK: - ARSCNViewDelegate
	func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        // Place content only for anchors found by plane detection.
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

        // Create a SceneKit plane to visualize the plane anchor using its position and extent.
        let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
        let planeNode = SCNNode(geometry: plane)
        planeNode.simdPosition = float3(planeAnchor.center.x, 0, planeAnchor.center.z)
        
        /*
         `SCNPlane` is vertically oriented in its local coordinate space, so
         rotate the plane to match the horizontal orientation of `ARPlaneAnchor`.
        */
        planeNode.eulerAngles.x = -.pi / 2
        
        // Make the plane visualization semitransparent to clearly show real-world placement.
        planeNode.opacity = 0.05
        
        /*
         Add the plane visualization to the ARKit-managed node so that it tracks
         changes in the plane anchor as plane estimation continues.
        */
        if !plane_found {
            cube = SCNBox(width: 0.1, height: 0.15, length: 0.3, chamferRadius: 0.03)
            // ambient, diffuse, specular, and shininess
            cube.firstMaterial?.lightingModel = SCNMaterial.LightingModel.phong
            cube.firstMaterial?.diffuse.contents = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.7)
            cube.firstMaterial?.shininess = 0.5
            cubeNode = SCNNode(geometry: cube)
            cubeNode.position = SCNVector3(planeAnchor.center.x, planeAnchor.center.y+Float(cube.height/2.0), planeAnchor.center.z)
            node.addChildNode(cubeNode)
            node.addChildNode(planeNode)
            // Vibrate when plane found
            plane_found = true
            AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        }
        
	}

    /// - Tag: UpdateARContent
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        // Update content only for plane anchors and nodes matching the setup created in `renderer(_:didAdd:for:)`.
        guard let planeAnchor = anchor as?  ARPlaneAnchor,
            let planeNode = node.childNodes.first,
            let plane = planeNode.geometry as? SCNPlane
            else { return }
        
        // Plane estimation may shift the center of a plane relative to its anchor's transform.
        planeNode.simdPosition = float3(planeAnchor.center.x, 0, planeAnchor.center.z)
        
        /*
         Plane estimation may extend the size of the plane, or combine previously detected
         planes into a larger one. In the latter case, `ARSCNView` automatically deletes the
         corresponding node for one plane, then calls this method to update the size of
         the remaining plane.
        */
        plane.width = CGFloat(planeAnchor.extent.x)
        plane.height = CGFloat(planeAnchor.extent.z)
        
    }
    
    var time_since_within_distance_vibration: UInt64 = 0
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if plane_found == true {
            let transform = SCNMatrix4(frame.camera.transform)
            let location = SCNVector3(transform.m41, transform.m42, transform.m43)
            let distance = location.distance(vector: cubeNode.convertPosition(cubeNode.position, to: nil))
            self.distance.text = String(format: "Distance (<0.4m): %.2f m", distance)
            if (distance < 0.4) {
                self.distance.textColor = .green
                within_distance = true
                self.cube.firstMaterial?.diffuse.contents = UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.5)
            } else {
                self.distance.textColor = .red
                within_distance = false
                self.cube.firstMaterial?.diffuse.contents = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.5)
            }
            if within_distance == true {
                //vibrate every 1.8 second
                if (UInt64(NSDate().timeIntervalSince1970 * 1000.0) > time_since_within_distance_vibration + 1800) || time_since_within_distance_vibration == 0 {
                    AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
                    time_since_within_distance_vibration = UInt64(NSDate().timeIntervalSince1970 * 1000.0)
                }
            }
        }
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }

    // MARK: - ARSessionObserver
	
	func sessionWasInterrupted(_ session: ARSession) {
		// Inform the user that the session has been interrupted, for example, by presenting an overlay.
		sessionInfoLabel.text = "Session was interrupted"
	}
	
	func sessionInterruptionEnded(_ session: ARSession) {
		// Reset tracking and/or remove existing anchors if consistent tracking is required.
		sessionInfoLabel.text = "Session interruption ended"
		resetTracking()
	}
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user.
        sessionInfoLabel.text = "Session failed: \(error.localizedDescription)"
        resetTracking()
    }

    // MARK: - Private methods

    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        let message: String

        switch trackingState {
        case .normal where frame.anchors.isEmpty:
            // No planes detected; provide instructions for this app's AR interactions.
            message = "Move the device around to detect horizontal surfaces."
            
        case .normal:
            // No feedback needed when tracking is normal and planes are visible.
            message = ""
            
        case .notAvailable:
            message = "Tracking unavailable."
            
        case .limited(.excessiveMotion):
            message = "Tracking limited - Move the device more slowly."
            
        case .limited(.insufficientFeatures):
            message = "Tracking limited - Point the device at an area with visible surface detail, or improve lighting conditions."
            
        case .limited(.initializing):
            message = "Initializing AR session."
            
        }

        sessionInfoLabel.text = message
        sessionInfoView.isHidden = message.isEmpty
    }

    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        //reset state
        plane_found = false
        within_distance = false
        angle_correct = false
        capture_complete = false
        have_turned_on_flash = false
    }
}
