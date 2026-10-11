import WidgetKit
import SwiftUI
import UIKit

/* 記一筆的桌面小工具（小方塊）：財產總額＋主頁那句話。
   資料是 App 寫在共用儲存區的 widget.json：{total, mood, lv}。App 每次畫主頁、內容有變就寫一次，
   原生那邊寫完會叫小工具重畫，所以這裡不用定時更新。 */

struct LedgerData: Decodable {
    var total: Int
    var mood: String
    var lv: String
}

/* 找共用儲存區：跟 App 裡的 SharedBox 同一套。SideStore 簽名時會在 group 名稱後面加團隊代號，
   真正的名稱要從小工具自己的 embedded.mobileprovision 讀。 */
enum SharedFile {
    static let baseGroup = "group.io.github.robinrn0419.shared"

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

    static func load() -> LedgerData? {
        let names = profileGroups().filter { $0.hasPrefix(baseGroup) } + [baseGroup]
        for name in names {
            guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: name),
                  let data = try? Data(contentsOf: dir.appendingPathComponent("widget.json")),
                  let d = try? JSONDecoder().decode(LedgerData.self, from: data)
            else { continue }
            return d
        }
        return nil
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let data: LedgerData?
}

struct Provider: TimelineProvider {
    static let sample = LedgerData(total: 52300, mood: "這個月很穩", lv: "good")

    func placeholder(in context: Context) -> Entry { Entry(date: .now, data: Provider.sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, data: SharedFile.load() ?? Provider.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now, data: SharedFile.load())], policy: .never))
    }
}

struct LedgerWidgetView: View {
    var entry: Entry

    /* 跟 App 主頁那句話同一組顏色（--mood-bad／warn／good），淺色、深色各一個 */
    static func color(_ lv: String) -> Color {
        let pair: (UInt32, UInt32)
        switch lv {
        case "bad": pair = (0xD70015, 0xFF453A)
        case "warn": pair = (0xC93400, 0xFF9F0A)
        default: pair = (0x248A3D, 0x30D158)
        }
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(pair.1) : ui(pair.0) })
    }

    /* 跟 App 的 fmt() 一樣：千分位，負數用「−」 */
    static func money(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "zh_TW")
        return (n < 0 ? "−" : "") + (f.string(from: NSNumber(value: abs(n))) ?? String(abs(n)))
    }

    var body: some View {
        /* 字盡量大、放不下才縮；三行靠在一起、整組上下置中（使用者說原本中間空太多、偏一邊）。邊距用系統預設。 */
        VStack(alignment: .leading, spacing: 4) {
            Text("財產總額")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
            if let d = entry.data {
                Text(LedgerWidgetView.money(d.total))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !d.mood.isEmpty {
                    Text(d.mood)
                        .font(.system(size: 17, weight: .semibold))  // 比數字低調，數字才是主角
                        .foregroundStyle(LedgerWidgetView.color(d.lv))
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                }
            } else {
                Text("打開記一筆一次，這裡就會顯示總額")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            /* 使用者說背景單調，選了「角落淡淡的大錢包」（像課堂薪水主頁方塊角落的大圖示），只露出一部分 */
            ZStack(alignment: .bottomTrailing) {
                Color(uiColor: .systemBackground)
                WalletMark()
                    .frame(width: 124, height: 124)
                    .offset(x: 22, y: 30)
            }
        }
    }
}

/* App 圖示那個錢包（SVG viewBox 100：綠卡片斜斜露出、錢包本體、扣帶、扣子），畫得很淡 */
struct WalletMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 100
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerRadius: r * s)
            }
            let turn = CGAffineTransform(translationX: 49 * s, y: 34 * s)
                .rotated(by: -10 * .pi / 180)
                .translatedBy(x: -49 * s, y: -34 * s)
            ctx.fill(rect(28, 20, 42, 28, 5).applying(turn), with: .color(Color(red: 0x78 / 255, green: 0xBC / 255, blue: 0x96 / 255).opacity(0.28)))
            ctx.fill(rect(18, 36, 64, 44, 9), with: .color(.primary.opacity(0.09)))
            ctx.fill(rect(56, 49, 30, 18, 7), with: .color(.primary.opacity(0.07)))
            ctx.fill(Path(ellipseIn: CGRect(x: 62.5 * s, y: 54.5 * s, width: 7 * s, height: 7 * s)), with: .color(.primary.opacity(0.12)))
        }
    }
}

@main
struct LedgerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LedgerTotal", provider: Provider()) { entry in
            LedgerWidgetView(entry: entry)
        }
        .configurationDisplayName("財產總額")
        .description("記一筆的財產總額，和這個月花錢的狀況。")
        .supportedFamilies([.systemSmall])
    }
}
