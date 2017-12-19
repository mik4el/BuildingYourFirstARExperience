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

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
	// MARK: - IBOutlets

    @IBOutlet weak var sessionInfoView: UIView!
	@IBOutlet weak var sessionInfoLabel: UILabel!
	@IBOutlet weak var sceneView: ARSCNView!

    @IBOutlet weak var rotX: UILabel!
    @IBOutlet weak var rotY: UILabel!
    @IBOutlet weak var rotZ: UILabel!
    
	// MARK: - View Life Cycle
	let manager = CMMotionManager()
    var plane_found = false
    var cube: SCNBox = SCNBox()
    var cubeNode: SCNNode = SCNNode()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        manager.gyroUpdateInterval = 0.1
        manager.accelerometerUpdateInterval = 0.1
        
        manager.startGyroUpdates()
        manager.startAccelerometerUpdates()
        
        let epsilon = 0.02
        let desired_rotation_z = -0.5 // range -1.0 to 1.0 for full rotation
        var time_started_desired_rotation: UInt64 = 0
        var capture_complete = false
        var time_started_capture_complete: UInt64 = 0
        var have_turned_on_flash = false
        
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 0.01
            manager.startDeviceMotionUpdates(to: OperationQueue.main) {
                [weak self] data, error in
                self?.rotX.text = String(format: "rotX: %.2f", data!.gravity.x)
                self?.rotY.text = String(format: "rotY: %.2f", data!.gravity.y)
                self?.rotZ.text = String(format: "rotZ: %.2f", data!.gravity.z)
                // Rewrite as explicit state machine
                if capture_complete || !(self?.plane_found)! {
                    if UInt64(NSDate().timeIntervalSince1970 * 1000.0) > time_started_capture_complete + 2000 {
                        capture_complete = false
                    }
                } else {
                    if data!.gravity.z < desired_rotation_z - epsilon || data!.gravity.z > desired_rotation_z + epsilon {
                        // Outside desired rotation
                        self?.rotZ.textColor = .white
                        time_started_desired_rotation = 0
                    }
                    else {
                        // Within desired rotation
                        self?.rotZ.textColor = .red
                        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
                        if (time_started_desired_rotation==0) {
                            time_started_desired_rotation = UInt64(NSDate().timeIntervalSince1970 * 1000.0)
                        }
                        else {
                            if UInt64(NSDate().timeIntervalSince1970 * 1000.0) > time_started_desired_rotation + 1000 {
                                // turn on light
                                if !have_turned_on_flash {
                                    self?.turnOnFlash()
                                    have_turned_on_flash = true
                                }
                            }
                            if UInt64(NSDate().timeIntervalSince1970 * 1000.0) > time_started_desired_rotation + 2000 {
                                // play capture sound and turn off flash
                                capture_complete = true
                                time_started_capture_complete = UInt64(NSDate().timeIntervalSince1970 * 1000.0)
                                self?.turnOffFlash()
                                have_turned_on_flash = false
                                AudioServicesPlaySystemSound(1108)
                                time_started_desired_rotation = 0
                            }
                        }
                    }
                }
            }
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
            cube = SCNBox(width: 0.1, height: 0.2, length: 0.3, chamferRadius: 0.03)
            // ambient, diffuse, specular, and shininess
            cube.firstMaterial?.lightingModel = SCNMaterial.LightingModel.phong
            cube.firstMaterial?.diffuse.contents = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.5)
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

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = SCNMatrix4(frame.camera.transform)
        let location = SCNVector3(transform.m41, transform.m42, transform.m43)
        let distance = location.distance(vector: cubeNode.convertPosition(cubeNode.position, to: nil))
        if (distance < 0.8) {
            self.cube.firstMaterial?.diffuse.contents = UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.5)
        } else {
            self.cube.firstMaterial?.diffuse.contents = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.5)
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
    }
}
