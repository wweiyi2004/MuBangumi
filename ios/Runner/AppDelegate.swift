import Flutter
import UIKit
import UserNotifications
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MuBangumiGallery") else { return }
    FlutterMethodChannel(name: "mubangumi/gallery", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        guard call.method == "savePng" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: Any],
              let bytes = args["bytes"] as? FlutterStandardTypedData,
              !bytes.data.isEmpty else {
          result(FlutterError(code: "invalid_image", message: "图片数据无效", details: nil)); return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          guard status == .authorized || status == .limited else {
            DispatchQueue.main.async { result(FlutterError(code: "permission_denied", message: "未获得相册保存权限，可在系统设置中允许后重试", details: nil)) }; return
          }
          PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = args["name"] as? String
            request.addResource(with: .photo, data: bytes.data, options: options)
          }) { success, error in
            DispatchQueue.main.async {
              if success { result("photos") }
              else { result(FlutterError(code: "gallery_save", message: error?.localizedDescription ?? "无法保存到相册", details: nil)) }
            }
          }
        }
      }
  }
}
