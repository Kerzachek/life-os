import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerLaunchAtStartupChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  /// Канал пакета launch_at_startup: вход в систему через SMAppService (macOS 13+).
  private func registerLaunchAtStartupChannel(_ messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "launch_at_startup", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard #available(macOS 13.0, *) else {
          result(FlutterError(
            code: "UNSUPPORTED", message: "Requires macOS 13 or later", details: nil))
          return
        }
        let service = SMAppService.mainApp
        switch call.method {
        case "launchAtStartupIsEnabled":
          result(service.status == .enabled)
        case "launchAtStartupSetEnabled":
          let enabled = (call.arguments as? [String: Any])?["setEnabledValue"] as? Bool ?? false
          do {
            if enabled {
              try service.register()
            } else {
              try service.unregister()
            }
            result(nil)
          } catch {
            result(FlutterError(
              code: "FAILED", message: error.localizedDescription, details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }
}
