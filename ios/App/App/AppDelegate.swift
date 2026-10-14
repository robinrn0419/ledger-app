import UIKit
import Capacitor
import WidgetKit

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
        bridge?.registerPluginInstance(GlassBarPlugin())
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
            if url.lastPathComponent == "widget.json" { WidgetCenter.shared.reloadAllTimelines() }  // 叫桌面小工具重畫
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

/* GlassBar：iOS 26 真正的 Liquid Glass 按鈕，疊在網頁上面（網頁那邊是 Capacitor.Plugins.GlassBar）。
   網頁用 set() 告訴它現在要哪些按鈕、上面寫什麼；按下時送 "tap" 事件回網頁，由網頁做原本的事。
   iOS 26 以前 info() 回 glass:false，網頁就繼續用自己畫的玻璃。 */
@objc(GlassBarPlugin)
public class GlassBarPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "GlassBarPlugin"
    public let jsName = "GlassBar"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "info", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "set", returnType: CAPPluginReturnPromise)
    ]

    private var buttons: [String: UIButton] = [:]
    private var seg: UISegmentedControl?

    @objc func info(_ call: CAPPluginCall) {
        let os = UIDevice.current.systemVersion
        if #available(iOS 26.0, *) {
            call.resolve(["glass": true, "os": os])
        } else {
            call.resolve(["glass": false, "os": os])
        }
    }

    /* set({back:{label,chevron}|null, next:{label,enabled}|null, primary:{label,plus}|null, more:true/false,
            seg:{x,y,w,h,value:'in'|'out'}|null})；seg 是輸入金額頁的「收入｜支出」，位置照網頁那顆量好傳過來 */
    @objc func set(_ call: CAPPluginCall) {
        let back = call.getObject("back")
        let next = call.getObject("next")
        let primary = call.getObject("primary")
        let more = call.getBool("more") ?? false
        let segInfo = call.getObject("seg")
        DispatchQueue.main.async {
            if #available(iOS 26.0, *) {
                self.buildIfNeeded()
                self.update("back", show: back != nil, title: back?["label"] as? String,
                            image: (back?["chevron"] as? Bool ?? true) ? "chevron.left" : nil, enabled: true)
                self.update("next", show: next != nil, title: next?["label"] as? String,
                            image: nil, enabled: next?["enabled"] as? Bool ?? true)
                self.update("primary", show: primary != nil, title: primary?["label"] as? String,
                            image: (primary?["plus"] as? Bool ?? false) ? "plus" : nil, enabled: true)
                self.update("more", show: more, title: nil, image: "ellipsis", enabled: true)
                self.updateSeg(segInfo)
            }
            call.resolve()
        }
    }

    @available(iOS 26.0, *)
    private func buildIfNeeded() {
        guard buttons.isEmpty, let root = bridge?.viewController?.view else { return }
        let safe = root.safeAreaLayoutGuide
        for id in ["back", "next", "more", "primary"] {
            let b = UIButton(configuration: (id == "next" || id == "primary") ? .prominentGlass() : .glass())
            b.translatesAutoresizingMaskIntoConstraints = false
            b.alpha = 0
            b.isHidden = true
            b.addAction(UIAction { [weak self] _ in
                self?.notifyListeners("tap", data: ["id": id])
            }, for: .touchUpInside)
            root.addSubview(b)
            buttons[id] = b
            switch id {
            case "back":
                NSLayoutConstraint.activate([
                    b.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
                    b.topAnchor.constraint(equalTo: safe.topAnchor, constant: 6),
                    b.heightAnchor.constraint(equalToConstant: 44)
                ])
            case "next":
                NSLayoutConstraint.activate([
                    b.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
                    b.topAnchor.constraint(equalTo: safe.topAnchor, constant: 6),
                    b.heightAnchor.constraint(equalToConstant: 44)
                ])
            case "more":
                NSLayoutConstraint.activate([
                    b.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
                    b.topAnchor.constraint(equalTo: safe.topAnchor, constant: 10),
                    b.widthAnchor.constraint(equalToConstant: 44),
                    b.heightAnchor.constraint(equalToConstant: 44)
                ])
            default:
                /* 鍵盤跳出來時跟著往上，收起來時停在安全區上面 */
                NSLayoutConstraint.activate([
                    b.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
                    b.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
                    b.bottomAnchor.constraint(equalTo: root.keyboardLayoutGuide.topAnchor, constant: -14),
                    b.heightAnchor.constraint(equalToConstant: 56)
                ])
            }
        }
    }

    @available(iOS 26.0, *)
    private func updateSeg(_ info: [String: Any]?) {
        guard let root = bridge?.viewController?.view else { return }
        guard let info = info else {
            if let s = seg, !s.isHidden {
                UIView.animate(withDuration: 0.2, animations: { s.alpha = 0 }) { _ in if s.alpha == 0 { s.isHidden = true } }
            }
            return
        }
        let s: UISegmentedControl
        if let old = seg {
            s = old
        } else {
            s = UISegmentedControl(items: ["收入", "支出"])
            s.alpha = 0
            s.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 16, weight: .medium)], for: .normal)
            s.addAction(UIAction { [weak self, weak s] _ in
                guard let s = s else { return }
                self?.notifyListeners("tap", data: ["id": s.selectedSegmentIndex == 0 ? "seg-in" : "seg-out"])
            }, for: .valueChanged)
            root.addSubview(s)
            seg = s
        }
        func num(_ k: String) -> CGFloat { CGFloat((info[k] as? NSNumber)?.doubleValue ?? 0) }
        s.frame = CGRect(x: num("x"), y: num("y"), width: num("w"), height: num("h"))
        let isIn = (info["value"] as? String) != "out"
        s.selectedSegmentIndex = isIn ? 0 : 1
        /* 選到收入時字是綠色，和網頁原本一樣 */
        s.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                                  .foregroundColor: isIn ? UIColor.systemGreen : UIColor.label], for: .selected)
        s.isHidden = false
        if s.alpha < 1 { UIView.animate(withDuration: 0.2) { s.alpha = 1 } }
    }

    @available(iOS 26.0, *)
    private func update(_ id: String, show: Bool, title: String?, image: String?, enabled: Bool) {
        guard let b = buttons[id] else { return }
        if show {
            var c: UIButton.Configuration = (id == "next" || id == "primary") ? .prominentGlass() : .glass()
            c.cornerStyle = .capsule
            let big = id == "primary"
            let weight: UIFont.Weight = id == "back" ? .medium : .semibold
            if let title = title, !title.isEmpty {
                c.title = title
                c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                    var a = a
                    a.font = UIFont.systemFont(ofSize: big ? 18 : 17, weight: weight)
                    return a
                }
            }
            if let image = image {
                c.image = UIImage(systemName: image, withConfiguration: UIImage.SymbolConfiguration(pointSize: big ? 17 : 16, weight: .semibold))
                c.imagePadding = 6
            }
            c.contentInsets = id == "more" ? NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                : NSDirectionalEdgeInsets(top: 0, leading: id == "back" ? 12 : 16, bottom: 0, trailing: 16)
            b.configuration = c
            b.isEnabled = enabled
            b.isHidden = false
            if b.alpha < 1 { UIView.animate(withDuration: 0.25) { b.alpha = 1 } }
        } else if !b.isHidden {
            UIView.animate(withDuration: 0.2, animations: { b.alpha = 0 }) { _ in
                if b.alpha == 0 { b.isHidden = true }
            }
        }
    }
}
