import Flutter
import UIKit
import UserNotifications
import Photos
import WebKit

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
    FlutterMethodChannel(name: "mubangumi/apple_website_cookies", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { call, result in
        let store = WKWebsiteDataStore.default().httpCookieStore
        if call.method == "readBgmCookies" {
          store.getAllCookies { cookies in
            let formatter = ISO8601DateFormatter()
            let values: [[String: Any]] = cookies.filter {
              $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == "bgm.tv"
            }.map { cookie in
              var value: [String: Any] = ["name": cookie.name, "value": cookie.value,
                "domain": cookie.domain, "path": cookie.path, "secure": cookie.isSecure, "http_only": cookie.isHTTPOnly]
              if let expires = cookie.expiresDate { value["expires_at"] = formatter.string(from: expires) }
              return value
            }
            DispatchQueue.main.async { result(values) }
          }
        } else if call.method == "setBgmCookie" {
          guard let args = call.arguments as? [String: Any], let header = args["header"] as? String,
                header.count <= 16384, !header.contains("\r"), !header.contains("\n"),
                let origin = URL(string: "https://bgm.tv"),
                let cookie = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": header], for: origin).first,
                cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == "bgm.tv" else {
            result(FlutterError(code: "invalid_cookie", message: "网站 Cookie 无效", details: nil)); return
          }
          store.setCookie(cookie) { DispatchQueue.main.async { result(nil) } }
        } else { result(FlutterMethodNotImplemented) }
      }
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
