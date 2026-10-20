import AppKit
import SwiftUI
import Foundation

enum Scalar: Codable, Equatable {
    case bool(Bool), number(Double), string(String), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else { self = .string(try c.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .bool(let v): try c.encode(v); case .number(let v): try c.encode(v); case .string(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    var bool: Bool? { if case .bool(let x) = self { return x }; return nil }
    var number: Double? { if case .number(let x) = self { return x }; return nil }
}
struct StateValue: Decodable { let code: Int; let value: Scalar?; let percent: Int? }
struct Choice: Decodable { let value: Double; let label: String }
struct Control: Decodable, Identifiable {
    let id, name, label, format: String
    let range: [Double]?
    let options: [Choice]
    let writable: Bool?
    let section, unitSymbol: String?
    var isWritable: Bool { writable != false }
    var unit: String { if let symbol=unitSymbol, !symbol.isEmpty { return symbol }; return name == "brightness" ? "%" : name == "color-temperature" ? "K" : name == "target-temperature" ? "°C" : "" }
}
struct Channel: Decodable, Identifiable { let id, name: String; let controls: [Control] }
struct Device: Decodable, Identifiable {
    let id, name, model, kind, group: String
    let channels: [Channel]
    let state: [String: StateValue]?
    let cachedOnline: Bool
    var controls: [Control] { channels.flatMap { $0.controls } }
    var powerControl: Control? { controls.first { $0.name == "on" } }
    var power: Bool? { guard let p = powerControl, let s = state?[p.id], s.code == 0 else { return nil }; return s.value?.bool }
    var symbol: String { kind == "fan" ? "fan.fill" : kind == "air-conditioner" ? "air.conditioner.horizontal.fill" : kind == "heater" ? "heater.vertical.fill" : kind == "switch" ? "switch.2" : name.contains("挂灯") ? "light.overhead.right.fill" : name.contains("沙发") ? "lamp.floor.fill" : "lightbulb.fill" }
    var shortName: String { name.replacingOccurrences(of: "显示器", with: "").replacingOccurrences(of: "全屋-", with: "") }
    func boolean(_ control: Control) -> Bool? {
        guard let value=state?[control.id], value.code == 0 else { return nil }; return value.value?.bool
    }
    func numeric(_ control: Control) -> Double? {
        guard let v = state?[control.id], v.code == 0 else { return nil }
        return control.name == "brightness" ? v.percent.map(Double.init) : v.value?.number
    }
    func display(_ control: Control) -> String {
        if control.format == "bool" { return boolean(control).map { $0 ? "开启" : "关闭" } ?? "未确认" }
        guard let v = numeric(control) else { return "未确认" }
        if control.name == "off-delay-time" && v == 0 { return "未定时" }
        if control.name == "fan-percent" { if v == 0 { return "自动" }; if v == 101 { return "强劲" } }
        if let choice = control.options.first(where: { $0.value == v }) { return choice.label }
        return String(format: v == floor(v) ? "%.0f" : "%.1f", v) + control.unit
    }
}
struct Scene: Decodable, Identifiable {
    let id, name: String
    let enabled: Bool
    let actionCount: Int
    let actionNames: [String]
    var symbol: String { name.contains("晚安") ? "moon.stars.fill" : name.contains("起床") ? "sunrise.fill" : name.contains("观影") ? "play.rectangle.fill" : name.contains("游戏") ? "gamecontroller.fill" : name.contains("离家") ? "door.left.hand.open" : name.contains("回家") ? "house.fill" : name.contains("专注") ? "scope" : "sparkles" }
}
struct WriteExpectation: Decodable {
    let deviceID, controlID: String
    let value: Scalar
    func matches(_ device: Device) -> Bool {
        guard device.id == deviceID, let state=device.state?[controlID], state.code == 0 else { return false }
        if case .number(let target)=value, case .number(let observed)=state.value { return abs(observed-target)<0.00001 }
        return state.value == value
    }
}
struct PendingChange { let expected: WriteExpectation; let expires: Date }
struct Reply: Decodable {
    let ok: Bool
    let error, message: String?
    let devices: [Device]?
    let scenes: [Scene]?
    let device: Device?
    let unsupported, warnings: [String]?
    let readbackConfirmed: Bool?
    let expected: WriteExpectation?
}
enum Page: String, CaseIterable { case favorites = "常用", lights = "灯光", climate = "温控", scenes = "场景"
    var symbol: String { switch self { case .favorites: return "star.fill"; case .lights: return "lightbulb.fill"; case .climate: return "fan.fill"; case .scenes: return "sparkles" } }
    var nsColor: NSColor { self == .scenes ? .systemPurple : self == .climate ? .systemCyan : self == .lights ? .systemOrange : .systemMint }
    var color: Color { Color(nsColor: nsColor) }
}
enum TouchMode { case overview, device, scene }

final class HomeModel: ObservableObject {
    @Published var devices: [Device] = []
    @Published var scenes: [Scene] = []
    @Published var unsupported: [String] = []
    @Published var page: Page = .favorites
    @Published var selectedDeviceID: String?
    @Published var selectedSceneID: String?
    @Published var busy = false
    @Published var message = "正在同步家庭…"
    @Published var failed = false
    @Published var lastUpdate: Date?
    @Published var query = ""
    @Published var globalAvailable = false
    @Published var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "favoriteDeviceIDs") ?? [])
    @Published var signedIn = false
    @Published var homes: [CloudHome] = []
    @Published var homeID = ""
    @Published var qrContent: String?
    @Published var loginStatus = "用手机米家扫码登录，中国大陆区。"
    @Published var loginBusy = false
    @Published var accountMessage = ""
    @Published var showAccount = false
    @Published var pending: [String:PendingChange] = [:]
    var readbackTask: Task<Void,Never>?
    var queuedStates=false
    var barVisible=false
    var windowVisible=true
    var lastStatePoll: Date?
    var pollInterval: TimeInterval { windowVisible || barVisible ? 10 : 60 }
    var backend: NativeBackend?
    var auth: Credentials?
    var loginFlow: LoginFlow?
    var loginTask: Task<Void,Never>?
    var operation: Task<Void,Never>?
    var generation = UUID()
    var homeName: String { homes.first { $0.id == homeID }?.name ?? "选择家庭" }
    var touchMode: TouchMode = .overview
    var touchControlID: String?
    var onChange: (() -> Void)?
    var timer: Timer?
    var selectedDevice: Device? { devices.first { $0.id == selectedDeviceID } }
    var selectedScene: Scene? { scenes.first { $0.id == selectedSceneID } }
    var filteredDevices: [Device] {
        devices.filter { d in
            let category = page == .favorites ? favorites.contains(d.id) : page == .lights ? d.group == "灯光" : page == .climate ? d.group == "温控" : false
            return category && (query.isEmpty || d.name.localizedCaseInsensitiveContains(query))
        }
    }
    var filteredScenes: [Scene] { scenes.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var activeCount: Int { devices.filter { $0.power == true }.count }
    var readableCount: Int { devices.filter { $0.power != nil }.count }
    var lastUpdateText: String { guard let lastUpdate = lastUpdate else { return "等待同步" }; return DateFormatter.localizedString(from: lastUpdate, dateStyle: .none, timeStyle: .medium) }

    func start() {
        Task { @MainActor in
            do { let saved = try await Task.detached(priority:.userInitiated,operation:{ try Vault.load() }).value; if let saved=saved { auth=saved; signedIn=true; await loadHomes() } }
            catch { loginStatus=error.localizedDescription }
        }
        timer = Timer(timeInterval:5,repeats:true) { [weak self] _ in
            guard let self=self, self.signedIn, self.backend != nil else { return }
            if Date().timeIntervalSince(self.lastStatePoll ?? .distantPast) >= self.pollInterval { self.requestStates() }
        }
        RunLoop.main.add(timer!,forMode:.common)
    }
    @MainActor func loadHomes() async {
        guard let auth=auth else { return }
        busy=true; accountMessage="正在读取家庭…"
        do {
            homes=try await CloudClient(auth).homes()
            busy=false
            let saved=UserDefaults.standard.string(forKey:"selectedHome."+opaque(auth.userId)) ?? ""
            if homes.contains(where:{$0.id == saved}) { selectHome(saved) }
            else { homeID=""; backend=nil; accountMessage=homes.isEmpty ? "账号下没有可用家庭。请确认米家地区为中国大陆。" : "请选择要控制的家庭。" }
        } catch { busy=false; failed=true; accountMessage=error.localizedDescription; message=accountMessage }
        onChange?()
    }
    func beginLogin() {
        guard !busy else { return }
        loginTask?.cancel(); loginFlow?.cancel()
        let flow=LoginFlow(); loginFlow=flow; loginBusy=true; qrContent=nil; loginStatus="正在申请二维码…"
        loginTask=Task { @MainActor in
            do {
                let (content,lp)=try await flow.qr(); try Task.checkCancellation()
                qrContent=content; loginStatus="打开手机米家 · 右上角 + · 扫一扫，并确认登录。"
                let saved=try await flow.finish(lp); try Task.checkCancellation()
                try Vault.save(saved)
                auth=saved; signedIn=true; loginBusy=false; qrContent=nil; loginStatus="登录成功"
                await loadHomes()
            } catch {
                if !Task.isCancelled { loginBusy=false; qrContent=nil; loginStatus=error.localizedDescription }
            }
        }
    }
    func cancelLogin() { loginTask?.cancel(); loginTask=nil; loginFlow?.cancel(); loginFlow=nil; loginBusy=false; qrContent=nil; loginStatus="登录已取消，可重新扫码。" }
    func selectHome(_ id: String) {
        guard !busy, let auth=auth, let home=homes.first(where:{$0.id == id}) else { return }
        generation=UUID(); operation?.cancel(); readbackTask?.cancel(); pending=[:]; queuedStates=false; lastStatePoll=nil; devices=[]; scenes=[]; unsupported=[]; selectedDeviceID=nil; selectedSceneID=nil; lastUpdate=nil; touchMode = .overview
        homeID=id; backend=NativeBackend(auth:auth,home:home)
        UserDefaults.standard.set(id,forKey:"selectedHome."+opaque(auth.userId))
        favorites=Set(UserDefaults.standard.stringArray(forKey:"favorites."+opaque(auth.userId,id)) ?? [])
        refresh()
    }
    func renewSession() {
        guard !busy, let auth=auth else { return }
        busy=true; accountMessage="正在续期登录…"
        Task { @MainActor in
            do { let flow=LoginFlow(); let next=try await flow.refresh(auth); try Vault.save(next); self.auth=next; backend?.client.auth=next; accountMessage="登录已续期"; busy=false; await loadHomes() }
            catch { busy=false; accountMessage=error.localizedDescription }
        }
    }
    func logout() {
        guard !busy else { return }
        do { try Vault.delete() } catch { accountMessage=error.localizedDescription; return }
        cancelLogin(); operation?.cancel(); readbackTask?.cancel(); pending=[:]; queuedStates=false; generation=UUID(); backend=nil; auth=nil; signedIn=false; homes=[]; homeID=""; devices=[]; scenes=[]; favorites=[]; unsupported=[]; selectedDeviceID=nil; selectedSceneID=nil; lastUpdate=nil; touchMode = .overview; showAccount=false; message="已退出登录"; onChange?()
    }
    var favoriteKey: String { "favorites."+opaque(auth?.userId ?? "",homeID) }
    func changePage(_ p: Page) { page = p; query = ""; touchMode = .overview; onChange?() }
    func selectDevice(_ d: Device) { selectedDeviceID = d.id; selectedSceneID = nil; touchMode = .device; touchControlID = d.controls.first { $0.name != "on" && $0.isWritable }?.id; onChange?(); requestStates([d.id]) }
    func selectScene(_ s: Scene) { selectedSceneID = s.id; touchMode = .scene; onChange?() }
    func back() { touchMode = .overview; onChange?() }
    func toggleFavorite(_ d: Device) {
        if favorites.contains(d.id) { favorites.remove(d.id) } else { favorites.insert(d.id) }
        UserDefaults.standard.set(Array(favorites), forKey: favoriteKey); onChange?()
    }
    func refresh() { guard !busy else { return }; call(["action": "snapshot"]) { [weak self] reply in self?.applySnapshot(reply) } }
    func pendingText(_ deviceID: String) -> String? { pending.values.contains { $0.expected.deviceID == deviceID } ? "指令已提交 · 等待云端确认" : nil }
    func requestStates(_ ids: [String]? = nil) {
        guard backend != nil else { return }
        if busy { queuedStates=true; return }
        var command: [String:Any] = ["action":"states"]
        if let ids=ids { command["devices"]=ids }
        call(command) { [weak self] reply in
            guard let self=self else { return }
            for d in reply.devices ?? [] { if let index=self.devices.firstIndex(where:{$0.id == d.id}) { self.devices[index]=d } }
            self.lastUpdate=Date(); self.reconcilePending()
        }
    }
    func reconcilePending(now: Date = Date()) {
        var confirmed=[String](), timedOut=false
        for (key,change) in pending {
            if let device=devices.first(where:{$0.id == change.expected.deviceID}), change.expected.matches(device) { pending.removeValue(forKey:key); confirmed.append(device.name) }
            else if now >= change.expires { pending.removeValue(forKey:key); timedOut=true }
        }
        if timedOut { failed=true; message="部分设置在 25 秒内未回读确认。当前显示最新云端状态，请勿连续重复发送。" }
        else if !confirmed.isEmpty { failed=false; message=confirmed.joined(separator:"、")+" · 设置已回读确认" }
        else if !pending.isEmpty { message="指令已接受，正在继续查询状态…" }
    }
    func scheduleReadback() {
        readbackTask?.cancel()
        let current=generation
        readbackTask=Task { @MainActor [weak self] in
            for delay in [2,3,5,10,6] {
                do { try await Task.sleep(nanoseconds:UInt64(delay)*1_000_000_000) } catch { return }
                guard let self=self, self.generation == current else { return }
                self.reconcilePending()
                guard !self.pending.isEmpty else { self.onChange?(); return }
                self.requestStates(Array(Set(self.pending.values.map { $0.expected.deviceID })))
            }
        }
    }
    private func applySnapshot(_ reply: Reply) {
        guard reply.ok else { return }
        devices = reply.devices ?? []; scenes = reply.scenes ?? []; unsupported = reply.unsupported ?? []; lastUpdate = Date(); reconcilePending()
        if UserDefaults.standard.object(forKey:favoriteKey) == nil {
            favorites=Set(devices.prefix(5).map(\.id))
            UserDefaults.standard.set(Array(favorites),forKey:favoriteKey)
        }
        if selectedDeviceID == nil { selectedDeviceID = devices.first?.id }
        if let warning = reply.warnings?.first { failed = true; message = warning }
    }
    func set(_ device: Device, _ control: Control, _ value: Any) {
        guard !busy else { return }
        call(["action": "set", "device": device.id, "control": control.id, "value": value]) { [weak self] reply in
            guard let self = self, reply.ok else { return }
            if let d = reply.device, let index = self.devices.firstIndex(where: { $0.id == d.id }) { self.devices[index] = d; self.lastUpdate = Date() }
            self.failed=false
            if let expected=reply.expected {
                let key=expected.deviceID+"/"+expected.controlID
                if reply.readbackConfirmed == true { self.pending.removeValue(forKey:key) }
                else { self.pending[key]=PendingChange(expected:expected,expires:Date().addingTimeInterval(25)); self.scheduleReadback() }
            }
            self.message=reply.readbackConfirmed == true ? "设置已回读确认" : "指令已接受，正在继续查询状态…"
        }
    }
    func runScene(_ scene: Scene) {
        guard scene.enabled && !busy else { return }
        call(["action": "scene", "scene": scene.id, "confirm": true]) { [weak self] reply in
            guard let self = self, reply.ok else { return }
            self.message = reply.message ?? "场景已提交"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.requestStates() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.requestStates() }
        }
    }
    private func call(_ command: [String:Any], complete: @escaping (Reply)->Void) {
        guard let backend=backend, !busy else { return }
        let current=generation
        let isRead=["states","snapshot"].contains(str(command["action"]))
        busy=true
        if isRead { lastStatePoll=Date() } else { failed=false }
        message=isRead ? "正在同步状态…" : "正在发送指令并回读…"; onChange?()
        operation=Task { @MainActor in
            do {
                let reply=try await backend.handle(command)
                guard current == generation else { return }
                busy=false
                if reply.ok { if isRead { failed=false }; message=reply.message ?? "已同步"; complete(reply) }
                else { failed=true; message=reply.error ?? "请求未被确认。" }
            } catch {
                guard current == generation else { return }
                busy=false; failed=true; message=error.localizedDescription
                if !isRead { Task { @MainActor [weak self] in try? await Task.sleep(nanoseconds:2_000_000_000); self?.requestStates() } }
            }
            onChange?()
            if queuedStates { queuedStates=false; requestStates() }
        }
    }
}
