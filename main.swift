// ClaudeMeter — 极简 Claude 用量菜单栏指示器
//
// 菜单栏只画一根竖条：填满程度 = 5 小时会话的剩余用量，无文字、无图标。
// 点击后的面板才展示详情（会话 / 每周 + 重置时间）。
//
// 凭证：sessionKey 存钥匙串(service=com.claudemeter.credentials)，org_id 存 UserDefaults。
// 轮询：每 1 分钟一次，点开面板时也会刷新。

import SwiftUI
import AppKit
import Security

// MARK: - 凭证

enum Creds {
    static let service = "com.claudemeter.credentials"
    static let account = "sessionKey"

    static func sessionKey() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static var orgID: String? { UserDefaults.standard.string(forKey: "org_id") }
}

// MARK: - 数据模型（只声明需要的字段，响应里其它 null 一律忽略）

struct Limit: Decodable {
    let utilization: Double?
    let resets_at: String?
}

struct Usage: Decodable {
    let five_hour: Limit?
    let seven_day: Limit?
}

// MARK: - 日期解析（claude.ai 用 6 位小数，带 .withFractionalSeconds 可解析）

func parseISO(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    let g = ISO8601DateFormatter()
    g.formatOptions = [.withInternetDateTime]
    return g.date(from: s)
}

// MARK: - 竖条绘制
//
// 画成 template 图（isTemplate = true），菜单栏会自动按浅色/深色反相成单色。
//
// 形状：轮廓恒定是一根胶囊（两端半圆，半径 = 宽/2），不随剩余比例变形。
// 填充满宽、从底部升起，裁剪进胶囊；填充高度 = 5 小时剩余比例。
// 填充**上方**那段淡色是"还没用到的部分"，不是边框（填充本身是满宽的，没有内缩）。

func batteryBarImage(fraction: Double?) -> NSImage {
    let w: CGFloat = 10, h: CGFloat = 18
    let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
        let rad = rect.width / 2
        let capsule = NSBezierPath(roundedRect: rect, xRadius: rad, yRadius: rad)

        // 未用到的那段：整根胶囊淡色；无数据时更淡
        NSColor.black.withAlphaComponent(fraction == nil ? 0.12 : 0.20).setFill()
        capsule.fill()

        // 已剩余的那段：满宽、贴底，裁剪进胶囊以保证两端半圆
        if let f = fraction {
            let fh = rect.height * max(0, min(1, f))
            if fh >= 0.5 {
                NSGraphicsContext.saveGraphicsState()
                capsule.addClip()
                NSColor.black.setFill()
                NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: fh).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        return true
    }
    img.isTemplate = true
    return img
}

// MARK: - 状态

@MainActor
final class Model: ObservableObject {
    @Published var session: Double?      // 5 小时已用 %
    @Published var weekly: Double?       // 每周已用 %
    @Published var sessionReset: Date?
    @Published var weeklyReset: Date?
    @Published var updated: Date?
    @Published var message: String?
    @Published var busy = false

    static func remaining(_ used: Double?) -> Double? {
        guard let u = used else { return nil }
        return max(0, min(100, 100 - u))
    }

    var sessionRemaining: Double? { Self.remaining(session) }
    var weeklyRemaining: Double? { Self.remaining(weekly) }

    /// 菜单栏竖条的填充比例（0~1），取 5 小时会话的剩余
    var barFraction: Double? {
        guard let r = sessionRemaining else { return nil }
        return r / 100
    }

    func refresh() async {
        guard let sk = Creds.sessionKey(), let org = Creds.orgID else {
            message = "凭证未配置"
            return
        }
        guard let url = URL(string: "https://claude.ai/api/organizations/\(org)/usage") else { return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("*/*", forHTTPHeaderField: "accept")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        req.setValue("sessionKey=\(sk)", forHTTPHeaderField: "Cookie")

        busy = true
        defer { busy = false }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { message = "无响应"; return }
            guard (200...299).contains(http.statusCode) else {
                message = "HTTP \(http.statusCode)"; return
            }
            let u = try JSONDecoder().decode(Usage.self, from: data)
            session = u.five_hour?.utilization
            weekly = u.seven_day?.utilization
            sessionReset = parseISO(u.five_hour?.resets_at)
            weeklyReset = parseISO(u.seven_day?.resets_at)
            updated = Date()
            message = nil
        } catch {
            message = "请求失败"
        }
    }
}

// MARK: - 面板（点击竖条后展示）

struct MeterRow: View {
    let title: String
    let remaining: Double?
    let reset: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(remaining.map { "剩余 \(Int($0.rounded()))%" } ?? "—")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(Color.secondary.opacity(0.62))
                        .frame(width: geo.size.width * max(0, min(1, (remaining ?? 0) / 100)))
                }
            }
            .frame(height: 5)
            if let r = reset {
                Text("重置 \(r.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PopoverView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            MeterRow(title: "会话 (5 小时)", remaining: model.sessionRemaining, reset: model.sessionReset)
            MeterRow(title: "每周 (7 天)", remaining: model.weeklyRemaining, reset: model.weeklyReset)

            Divider()

            HStack(spacing: 7) {
                if model.busy {
                    ProgressView().controlSize(.small)
                } else if let m = model.message {
                    Text(m).font(.system(size: 10)).foregroundStyle(.secondary)
                } else if let u = model.updated {
                    Text("更新于 \(u.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("立即刷新")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("退出 ClaudeMeter")
            }
        }
        .padding(14)
        .frame(width: 252)
    }
}

// MARK: - App

@main
struct ClaudeMeterApp: App {
    @StateObject private var model: Model

    init() {
        let m = Model()
        _model = StateObject(wrappedValue: m)
        Task { @MainActor in
            await m.refresh()
            let t = Timer(timeInterval: 60, repeats: true) { _ in
                Task { @MainActor in await m.refresh() }
            }
            RunLoop.main.add(t, forMode: .common)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .task { await model.refresh() }
        } label: {
            // 只有一根竖条：无文字、无图标
            Image(nsImage: batteryBarImage(fraction: model.barFraction))
        }
        .menuBarExtraStyle(.window)
    }
}
