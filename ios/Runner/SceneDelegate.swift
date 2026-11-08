import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
      options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      (UIApplication.shared.delegate as? AppDelegate)?.handleCaptureURL(context.url)
    }
  }
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let remaining = URLContexts.filter {
      !((UIApplication.shared.delegate as? AppDelegate)?.handleCaptureURL($0.url) ?? false)
    }
    if !remaining.isEmpty { super.scene(scene, openURLContexts: Set(remaining)) }
  }
}
