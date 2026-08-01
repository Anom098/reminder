import AVFoundation
import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Plugins used from the notification background isolate must be registered
    // explicitly; the default registrant only covers the main isolate.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    // Deliver banners while the app is foregrounded (iOS 10+).
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    configureAudioSession()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Allows spoken reminders to be heard while other audio plays and while the
  /// device is locked, without permanently ducking the user's music.
  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playback,
        mode: .spokenAudio,
        options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
      )
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      NSLog("VoiceReminder: failed to configure AVAudioSession — \(error)")
    }
  }
}
