import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Grid's own channels. Registered after the generated plugins so a name
    // collision would surface here rather than silently losing ours.
    TextRecogniserPlugin.register(
      with: engineBridge.pluginRegistry.registrar(forPlugin: "TextRecogniserPlugin")!
    )
  }
}
