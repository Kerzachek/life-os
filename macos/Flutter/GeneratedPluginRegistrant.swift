//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import google_sign_in_ios
import local_notifier
import package_info_plus
import url_launcher_macos

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  GoogleSignInPlugin.register(with: registry.registrar(forPlugin: "GoogleSignInPlugin"))
  LocalNotifierPlugin.register(with: registry.registrar(forPlugin: "LocalNotifierPlugin"))
  FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
  UrlLauncherPlugin.register(with: registry.registrar(forPlugin: "UrlLauncherPlugin"))
}
