import UIKit
import Capacitor

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/* 換掉 Capacitor 預設的畫面控制器，只為了把下面的 SharedBox 掛上去（SceneDelegate.swift 用這個；Main.storyboard 其實沒用到）。 */
class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(SharedBoxPlugin())
    }
}

/* SharedBox：課堂薪水和記一筆的共用儲存區（App Group），在網頁那邊是 Capacitor.Plugins.SharedBox。
   兩個 App 的 App.entitlements 都寫 group.io.github.robinrn0419.shared；SideStore 簽名時會在後面
   加上簽名帳號的團隊代號，所以真正的名稱要從 App 裡的 embedded.mobileprovision 讀出來。 */
@objc(SharedBoxPlugin)
public class SharedBoxPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SharedBoxPlugin"
    public let jsName = "SharedBox"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "info", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "write", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "read", returnType: CAPPluginReturnPromise)
    ]

    static let baseGroup = "group.io.github.robinrn0419.shared"

    /* 簽名檔裡列出的所有 App Group */
    static func profileGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex),
              let xml = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
              let ent = plist["Entitlements"] as? [String: Any],
              let groups = ent["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups
    }

    /* 找到能用的共用資料夾：名稱以 baseGroup 開頭、而且真的寫得進去 */
    static func container() -> (group: String, url: URL)? {
        let names = profileGroups().filter { $0.hasPrefix(baseGroup) } + [baseGroup]
        for name in names {
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: name) else { continue }
            let probe = url.appendingPathComponent(".probe")
            if (try? Data("ok".utf8).write(to: probe)) != nil { return (name, url) }
        }
        return nil
    }

    static func fileURL(_ call: CAPPluginCall) -> URL? {
        guard let name = call.getString("name"), !name.isEmpty, !name.contains("/"), let box = container() else { return nil }
        return box.url.appendingPathComponent(name)
    }

    @objc func info(_ call: CAPPluginCall) {
        let box = SharedBoxPlugin.container()
        call.resolve([
            "ok": box != nil,
            "group": box?.group ?? "",
            "groups": SharedBoxPlugin.profileGroups()
        ])
    }

    @objc func write(_ call: CAPPluginCall) {
        guard let url = SharedBoxPlugin.fileURL(call) else { return call.reject("沒有共用儲存區") }
        do {
            try Data((call.getString("text") ?? "").utf8).write(to: url, options: .atomic)
            call.resolve()
        } catch {
            call.reject(error.localizedDescription)
        }
    }

    @objc func read(_ call: CAPPluginCall) {
        guard let url = SharedBoxPlugin.fileURL(call) else { return call.reject("沒有共用儲存區") }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            return call.resolve(["text": NSNull()])
        }
        call.resolve(["text": text])
    }
}
