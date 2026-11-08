import UIKit
import Capacitor
import WidgetKit
import AppIntents

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        if #available(iOS 17.0, *) {
            SiriBox.log("App 啟動（" + (application.applicationState == .background ? "背景" : "前景") + "）")
        }
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

/* ---------- Siri（App Intents，iOS 17 起） ----------
   網頁每次畫主頁時寫 siri.json（總額、那句話、本月收支、所有類別的名稱），Siri 從這裡讀；
   Siri 記的帳先放進 siri-inbox.json，App 下次打開時收進紀錄。總額和小工具先在這裡加減，不用等 App 打開。 */
@available(iOS 17.0, *)
enum SiriBox {
    static func url(_ name: String) -> URL? {
        SharedBoxPlugin.container()?.url.appendingPathComponent(name)
    }
    static func read(_ name: String) -> Any? {
        guard let u = url(name), let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
    static func write(_ name: String, _ obj: Any) {
        guard let u = url(name), let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
        try? d.write(to: u, options: .atomic)
    }
    static func dateText(_ format: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = format
        return f.string(from: Date())
    }
    static func money(_ n: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: n)) ?? String(Int(n))
    }
    static func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }

    /* 查問題用：最近 12 件事（App 啟動、Siri 叫到哪個指令），網頁在「資料與備份」最下面顯示 */
    static func log(_ msg: String) {
        var list = read("siri-log.json") as? [String] ?? []
        list.append(dateText("M/d HH:mm:ss") + " " + msg)
        if list.count > 12 { list.removeFirst(list.count - 12) }
        write("siri-log.json", list)
    }

    /* 照說的話找類別：完全一樣的最優先，越細的層越優先；同分取前面的（支出排在收入前面） */
    static func match(_ spoken: String, _ cats: [[String: Any]]) -> [String: Any]? {
        var best: [String: Any]? = nil
        var bestScore = 0
        for c in cats {
            let keys = c["keys"] as? [String] ?? []
            var score = 0
            for (i, k) in keys.enumerated() where !k.isEmpty {
                var sc = 0
                if k == spoken { sc = 100 - i * 20 }
                else if k.count >= 2 && spoken.contains(k) { sc = 60 - i * 10 }
                else if spoken.count >= 2 && k.contains(spoken) { sc = 40 - i * 10 }
                score = max(score, sc)
            }
            if score > 0 { score -= keys.count }  /* 同樣分數時，大類比底下的「其他」優先 */
            if score > bestScore { bestScore = score; best = c }
        }
        return best
    }
}

@available(iOS 17.0, *)
struct AddRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "記一筆"
    static let description: IntentDescription? = IntentDescription("用說的記一筆帳，例如「午餐 120」")
    static let openAppWhenRun: Bool = false  /* 不打開 App，直接在背景回答 */
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed  /* 鎖定時也能用 */
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "金額", requestValueDialog: IntentDialog("多少錢？"))
    var amount: Int

    @Parameter(title: "類別", requestValueDialog: IntentDialog("記在什麼？例如午餐、計程車、月薪"))
    var item: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriBox.log("Siri：記一筆 \(amount) \(item)")
        guard amount > 0 else { return .result(dialog: "金額要大於 0 喔") }
        guard var info = SiriBox.read("siri.json") as? [String: Any] else {
            return .result(dialog: "請先打開一次記一筆，Siri 才知道有哪些類別")
        }
        let spoken = item.trimmingCharacters(in: .whitespacesAndNewlines)
        let cats = info["cats"] as? [[String: Any]] ?? []
        var kind = "out", cat = "out-other", label = "其他・雜項", note = ""
        var sub: Any = "misc", sub2: Any = NSNull()
        if let c = SiriBox.match(spoken, cats) {
            kind = c["kind"] as? String ?? "out"
            cat = c["cat"] as? String ?? cat
            sub = c["sub"] ?? NSNull()
            sub2 = c["sub2"] ?? NSNull()
            label = c["label"] as? String ?? spoken
        } else {
            note = spoken  /* 找不到類別：先記在其他・雜項，說的話放在備註 */
        }
        let now = Date()
        let rec: [String: Any] = [
            "id": "s" + String(Int(now.timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 1000...9999)),
            "kind": kind, "amt": amount, "cat": cat, "sub": sub, "sub2": sub2,
            "date": SiriBox.dateText("yyyy-MM-dd"), "note": note, "at": Int(now.timeIntervalSince1970 * 1000)
        ]
        var inbox = SiriBox.read("siri-inbox.json") as? [[String: Any]] ?? []
        inbox.append(rec)
        SiriBox.write("siri-inbox.json", inbox)

        /* 總額、本月收支先跟著加減，馬上問「還有多少錢」才會對 */
        let amt = Double(amount)
        let mk = SiriBox.dateText("yyyy-MM")
        if (info["mk"] as? String) != mk { info["mk"] = mk; info["mIn"] = 0; info["mOut"] = 0; info["mSave"] = 0 }
        let total = SiriBox.num(info["total"]) + (kind == "in" ? amt : -amt)
        info["total"] = total
        if kind == "in" { info["mIn"] = SiriBox.num(info["mIn"]) + amt } else { info["mOut"] = SiriBox.num(info["mOut"]) + amt }
        if cat == "out-other" && (sub as? String) == "saving" { info["mSave"] = SiriBox.num(info["mSave"]) + amt }
        SiriBox.write("siri.json", info)
        if var w = SiriBox.read("widget.json") as? [String: Any] {
            w["total"] = Int(total.rounded())
            SiriBox.write("widget.json", w)
            WidgetCenter.shared.reloadAllTimelines()
        }

        let sign = kind == "in" ? "收入" : "支出"
        var say = "已記下\(sign)：\(label) \(SiriBox.money(amt)) 元"
        if !note.isEmpty { say = "沒有「\(spoken)」這個類別，先記在其他・雜項 \(SiriBox.money(amt)) 元，備註寫\(spoken)" }
        return .result(dialog: IntentDialog(stringLiteral: say + "。現在有 \(SiriBox.money(total)) 元"))
    }
}

@available(iOS 17.0, *)
struct TotalIntent: AppIntent {
    static let title: LocalizedStringResource = "還有多少錢"
    static let description: IntentDescription? = IntentDescription("說出財產總額和主頁那句話")
    static let openAppWhenRun: Bool = false  /* 不打開 App，直接在背景回答 */
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed  /* 鎖定時也能用 */
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriBox.log("Siri：還有多少錢")
        guard let info = SiriBox.read("siri.json") as? [String: Any] else {
            return .result(dialog: "請先打開一次記一筆")
        }
        var say = "你現在有 \(SiriBox.money(SiriBox.num(info["total"]))) 元"
        if let mood = info["mood"] as? String, !mood.isEmpty { say += "。\(mood)" }
        return .result(dialog: IntentDialog(stringLiteral: say))
    }
}

@available(iOS 17.0, *)
struct MonthIntent: AppIntent {
    static let title: LocalizedStringResource = "這個月花多少"
    static let description: IntentDescription? = IntentDescription("說出這個月的收入和支出")
    static let openAppWhenRun: Bool = false  /* 不打開 App，直接在背景回答 */
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed  /* 鎖定時也能用 */
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriBox.log("Siri：這個月花多少")
        guard let info = SiriBox.read("siri.json") as? [String: Any] else {
            return .result(dialog: "請先打開一次記一筆")
        }
        let same = (info["mk"] as? String) == SiriBox.dateText("yyyy-MM")
        let mIn = same ? SiriBox.num(info["mIn"]) : 0
        let mOut = same ? SiriBox.num(info["mOut"]) : 0
        let mSave = same ? SiriBox.num(info["mSave"]) : 0
        var say = "這個月支出 \(SiriBox.money(mOut)) 元，收入 \(SiriBox.money(mIn)) 元"
        if mSave > 0 { say += "，支出裡有 \(SiriBox.money(mSave)) 元是存錢" }
        return .result(dialog: IntentDialog(stringLiteral: say))
    }
}

/* 不用自己設定捷徑，直接對 Siri 說就能用；中文說法在 zh-Hant.lproj/AppShortcuts.strings */
@available(iOS 17.0, *)
struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddRecordIntent(),
                    phrases: ["用\(.applicationName)記帳", "\(.applicationName)記帳", "在\(.applicationName)記帳"],
                    shortTitle: "記一筆", systemImageName: "square.and.pencil")
        AppShortcut(intent: TotalIntent(),
                    phrases: ["\(.applicationName)還有多少錢", "我在\(.applicationName)還有多少錢"],
                    shortTitle: "還有多少錢", systemImageName: "dollarsign.circle")
        AppShortcut(intent: MonthIntent(),
                    phrases: ["\(.applicationName)這個月花多少", "\(.applicationName)這個月花了多少"],
                    shortTitle: "這個月花多少", systemImageName: "calendar")
    }
}
