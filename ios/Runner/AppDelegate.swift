import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushChannel: FlutterMethodChannel?
  private var registration: FlutterResult?
  private var registrationTimeout: DispatchWorkItem?
  private var opened: [String: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.chaen.mwomeogeo/nudges",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    pushChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "register":
        let ask = (call.arguments as? [String: Any])?["ask"] as? Bool ?? false
        let center = UNUserNotificationCenter.current()
        if ask {
          center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { self.register(granted, result: result) }
          }
        } else {
          center.getNotificationSettings { settings in
            let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            DispatchQueue.main.async { self.register(allowed, result: result) }
          }
        }
      case "takeOpen":
        result(self.opened)
        self.opened = nil
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func register(_ allowed: Bool, result: @escaping FlutterResult) {
    guard allowed else { result(nil); return }
    guard registration == nil else {
      result(FlutterError(code: "busy", message: "Registration is pending", details: nil))
      return
    }
    registration = result
    let timeout = DispatchWorkItem { [weak self] in
      self?.finishRegistration(FlutterError(code: "timeout", message: "APNs registration timed out", details: nil))
    }
    registrationTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
    UIApplication.shared.registerForRemoteNotifications()
  }

  private func finishRegistration(_ value: Any?) {
    registrationTimeout?.cancel()
    registrationTimeout = nil
    let result = registration
    registration = nil
    result?(value)
  }

  override func application(_ application: UIApplication,
      didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    let setting = Bundle.main.object(forInfoDictionaryKey: "MealPushEnvironment") as? String
    finishRegistration(["token": token, "environment": setting == "development" ? "sandbox" : "production"])
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication,
      didFailToRegisterForRemoteNotificationsWithError error: Error) {
    finishRegistration(FlutterError(code: "registration_failed", message: "APNs registration failed", details: nil))
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
      willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list, .sound])
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
      didReceive response: UNNotificationResponse,
      withCompletionHandler completionHandler: @escaping () -> Void) {
    let info = response.notification.request.content.userInfo
    if let tableId = info["tableId"] as? String {
      opened = ["tableId": tableId]
      pushChannel?.invokeMethod("opened", arguments: opened)
    }
    completionHandler()
  }
}
