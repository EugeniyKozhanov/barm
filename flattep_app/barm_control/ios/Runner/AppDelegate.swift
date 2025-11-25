import Flutter
import UIKit
import MediaPlayer
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var volumeChannel: FlutterMethodChannel?
  private var volumeEventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var volumeButtonsEnabled = false
  private var volumeObserver: NSKeyValueObservation?
  private var audioSession: AVAudioSession?
  private var lastVolume: Float = 0.5
  private var volumeButtonPressed = false
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    let controller = window?.rootViewController as! FlutterViewController
    
    // Setup method channel
    volumeChannel = FlutterMethodChannel(
      name: "com.barm.control/volume",
      binaryMessenger: controller.binaryMessenger
    )
    
    volumeChannel?.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "enableVolumeButtons":
        self?.enableVolumeButtons()
        result(true)
      case "disableVolumeButtons":
        self?.disableVolumeButtons()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Setup event channel
    volumeEventChannel = FlutterEventChannel(
      name: "com.barm.control/volume_events",
      binaryMessenger: controller.binaryMessenger
    )
    
    volumeEventChannel?.setStreamHandler(VolumeStreamHandler(
      onListen: { [weak self] sink in
        self?.eventSink = sink
      },
      onCancel: { [weak self] in
        self?.eventSink = nil
      }
    ))
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func enableVolumeButtons() {
    volumeButtonsEnabled = true
    
    // Setup audio session
    audioSession = AVAudioSession.sharedInstance()
    try? audioSession?.setActive(true)
    
    // Store current volume
    lastVolume = audioSession?.outputVolume ?? 0.5
    
    // Observe volume changes
    volumeObserver = audioSession?.observe(\.outputVolume, options: [.new]) { [weak self] (session, change) in
      guard let self = self, self.volumeButtonsEnabled else { return }
      
      if let newVolume = change.newValue {
        // Detect button press (volume changed)
        if newVolume != self.lastVolume {
          let button = newVolume > self.lastVolume ? "up" : "down"
          
          // Send pressed event
          if !self.volumeButtonPressed {
            self.volumeButtonPressed = true
            self.eventSink?(["button": button, "pressed": true])
            
            // Schedule release event after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
              if let self = self, self.volumeButtonPressed {
                self.volumeButtonPressed = false
                self.eventSink?(["button": button, "pressed": false])
              }
            }
          }
          
          // Reset volume to prevent actual volume change
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.setSystemVolume(self.lastVolume)
          }
        }
      }
    }
  }
  
  private func disableVolumeButtons() {
    volumeButtonsEnabled = false
    volumeObserver?.invalidate()
    volumeObserver = nil
    try? audioSession?.setActive(false)
  }
  
  private func setSystemVolume(_ volume: Float) {
    let volumeView = MPVolumeView()
    if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
        slider.value = volume
      }
    }
  }
}

class VolumeStreamHandler: NSObject, FlutterStreamHandler {
  private let onListenCallback: (FlutterEventSink?) -> Void
  private let onCancelCallback: () -> Void
  
  init(onListen: @escaping (FlutterEventSink?) -> Void, onCancel: @escaping () -> Void) {
    self.onListenCallback = onListen
    self.onCancelCallback = onCancel
  }
  
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    onListenCallback(events)
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancelCallback()
    return nil
  }
}
