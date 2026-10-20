import Foundation
import CryptoKit
import Security

struct CloudError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
    init(_ text: String) { self.text = text }
}
func json(_ data: Data) throws -> [String:Any] {
    let prefix = Data("&&&START&&&".utf8)
    let clean = data.starts(with:prefix) ? data.dropFirst(prefix.count) : data[...]
    guard let obj = try JSONSerialization.jsonObject(with:Data(clean)) as? [String:Any] else { throw CloudError("服务器响应格式不符。") }; return obj
}
func str(_ x: Any?) -> String { x.map { String(describing:$0) } ?? "" }
func opaque(_ parts: String...) -> String { SHA256.hash(data:Data(parts.joined(separator:"|").utf8)).map { String(format:"%02x",$0) }.joined().prefix(20).description }
func form(_ pairs: [(String,String)]) -> Data {
    let allowed = CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    return Data(pairs.map { ($0.0.addingPercentEncoding(withAllowedCharacters:allowed) ?? "") + "=" + ($0.1.addingPercentEncoding(withAllowedCharacters:allowed) ?? "") }.joined(separator:"&").utf8)
}
func rc4(_ key: Data, _ input: Data) -> Data {
    let k = Array(key); guard !k.isEmpty else { return Data() }
    var s = Array(0...255), j = 0
    for i in 0...255 { j = (j+s[i]+Int(k[i%k.count]))%256; s.swapAt(i,j) }
    var i = 0; j = 0; var out = [UInt8](); let bytes = Array(input)
    for n in 0..<(1024+bytes.count) { i=(i+1)%256; j=(j+s[i])%256; s.swapAt(i,j); let v=UInt8(s[(s[i]+s[j])%256]); if n>=1024 { out.append(bytes[n-1024]^v) } }
    return Data(out)
}
func signature(_ path: String, _ pairs: [(String,String)], _ signed: String) -> String {
    let text = (["POST",path] + pairs.map { $0.0+"="+$0.1 } + [signed]).joined(separator:"&")
    return Data(Insecure.SHA1.hash(data:Data(text.utf8))).base64EncodedString()
}
struct CloudHome: Identifiable, Equatable {
    let id, name, owner: String
}
struct Credentials: Codable {
    var userId = "", cUserId = "", ssecurity = "", serviceToken = "", passToken = ""
    var deviceId = UUID().uuidString.replacingOccurrences(of:"-",with:"").prefix(16).description
    var passO = UUID().uuidString.replacingOccurrences(of:"-",with:"").prefix(16).description.lowercased()
    var ua = ""
    init() {
        let id = UUID().uuidString.replacingOccurrences(of:"-",with:"").uppercased()
        ua = "Android-15-11.0.701-Xiaomi-23046RP50C-OS2.0.212.0.VMYCNXM-\(id)\(id.prefix(8))-CN-\(id)-\(id)-SmartHome-MI_APP_STORE-\(id)\(id.prefix(8))|\(id)\(id.prefix(8))|\(passO)-64"
    }
}
enum Vault {
    static let service = "app.homedeck.share.xiaomi.cn"
    static var query: [String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"session"] }
    static func load() throws -> Credentials? {
        var q=query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
        var item: CFTypeRef?; let status=SecItemCopyMatching(q as CFDictionary,&item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data=item as? Data else { throw CloudError("无法读取家控台钥匙串，请允许本 App 访问自己的登录项。") }
        return try JSONDecoder().decode(Credentials.self,from:data)
    }
    static func save(_ credentials: Credentials) throws {
        let bytes=try JSONEncoder().encode(credentials)
        let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var q=query; q[kSecValueData as String]=bytes; q[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary,nil) == errSecSuccess else { throw CloudError("无法安全保存登录信息，未写入普通文件。") }
        } else if status != errSecSuccess { throw CloudError("无法更新钥匙串登录信息。") }
    }
    static func delete() throws { let s=SecItemDelete(query as CFDictionary); guard s == errSecSuccess || s == errSecItemNotFound else { throw CloudError("未能删除钥匙串登录项。") } }
}
// Redirects only within Xiaomi's authentication domains. Cloud and public-spec requests forbid redirects.
final class Network: NSObject, URLSessionTaskDelegate {
    let login: Bool
    init(login: Bool) { self.login=login }
    lazy var session: URLSession = {
        let c=URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest=25; c.timeoutIntervalForResource=150
        c.httpCookieAcceptPolicy = .always
        return URLSession(configuration:c,delegate:self,delegateQueue:nil)
    }()
    static func loginURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let h=url.host?.lowercased(), url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return h == "xiaomi.com" || h.hasSuffix(".xiaomi.com") || h == "mijia.tech" || h.hasSuffix(".mijia.tech") || h == "io.mi.com" || h.hasSuffix(".io.mi.com")
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,newRequest request: URLRequest,completionHandler: @escaping (URLRequest?)->Void) {
        completionHandler(login && request.url.map(Self.loginURL) == true ? request : nil)
    }
    func fetch(_ request: URLRequest) async throws -> Data {
        do {
            let (data,response)=try await session.data(for:request)
            guard let r=response as? HTTPURLResponse else { throw CloudError("没有收到有效服务器响应。") }
            if r.statusCode == 401 || r.statusCode == 403 { throw CloudError("登录已失效或请求受限，请重新扫码。") }
            guard r.statusCode == 200 else { throw CloudError("服务器 HTTP \(r.statusCode)；请求未完成，控制操作不会自动重发。") }
            guard data.count <= 16*1024*1024 else { throw CloudError("服务器响应过大。") }; return data
        } catch is CancellationError { throw CancellationError() }
        catch let e as CloudError { throw e }
        catch { if Task.isCancelled { throw CancellationError() }; throw CloudError("网络请求未完成；如刚发送了控制命令，请先刷新状态，避免重复操作。") }
    }
    func reset() { session.invalidateAndCancel() }
}
final class LoginFlow {
    let network=Network(login:true)
    var credentials=Credentials()
    func request(_ url: URL) -> URLRequest {
        var r=URLRequest(url:url); r.setValue(credentials.ua,forHTTPHeaderField:"User-Agent")
        r.setValue("deviceId=\(credentials.deviceId);pass_o=\(credentials.passO);passToken=\(credentials.passToken);userId=\(credentials.userId);cUserId=\(credentials.cUserId);uLocale=zh_CN",forHTTPHeaderField:"Cookie")
        return r
    }
    func service() async throws -> [String:Any] {
        try json(await network.fetch(request(URL(string:"https://account.xiaomi.com/pass/serviceLogin?_json=true&sid=mijia&_locale=zh_CN")!)))
    }
    func qr() async throws -> (String,URL) {
        let result=try await service()
        guard let location=URL(string:str(result["location"])), Network.loginURL(location), let query=URLComponents(url:location,resolvingAgainstBaseURL:false)?.queryItems else { throw CloudError("小米登录入口已变化，请稍后重试。") }
        var url=URLComponents(string:"https://account.xiaomi.com/longPolling/loginUrl")!
        let extra=["theme":"","bizDeviceType":"","_hasLogo":"false","_qrsize":"240","_dc":str(Int(Date().timeIntervalSince1970*1000))]
        url.queryItems=query.filter { extra[$0.name] == nil } + extra.map { URLQueryItem(name:$0.key,value:$0.value) }
        let qr=try json(await network.fetch(request(url.url!)))
        guard (qr["code"] as? Int ?? 0) == 0, let content=qr["loginUrl"] as? String, let qrURL=URL(string:content), Network.loginURL(qrURL), let lp=URL(string:str(qr["lp"])), (lp.host == "account.xiaomi.com" || lp.host?.hasSuffix(".account.xiaomi.com") == true), Network.loginURL(lp) else { throw CloudError("未取得可用登录二维码，请刷新重试。") }
        return (content,lp)
    }
    func finish(_ url: URL) async throws -> Credentials {
        var r=request(url); r.timeoutInterval=125
        let data=try json(await network.fetch(r))
        guard data["code"] as? Int == 0 else { throw CloudError("二维码已过期或登录未确认，请刷新二维码。") }
        credentials.userId=str(data["userId"]); credentials.cUserId=str(data["cUserId"]); credentials.ssecurity=str(data["ssecurity"]); credentials.passToken=str(data["passToken"])
        try await follow(data)
        guard !credentials.userId.isEmpty, !credentials.ssecurity.isEmpty, !credentials.serviceToken.isEmpty else { throw CloudError("登录回调缺少必要信息，请重新扫码。") }
        return credentials
    }
    func follow(_ data: [String:Any]) async throws {
        guard let url=URL(string:str(data["location"])), Network.loginURL(url) else { throw CloudError("小米登录回调地址无法验证。") }
        _=try await network.fetch(request(url))
        let cookies=network.session.configuration.httpCookieStorage?.cookies ?? []
        credentials.serviceToken=cookies.first { $0.name == "serviceToken" && ($0.domain.contains("mijia.tech") || $0.domain.contains("io.mi.com")) }?.value ?? ""
    }
    func refresh(_ saved: Credentials) async throws -> Credentials {
        credentials=saved; let data=try await service()
        guard data["code"] as? Int == 0 else { throw CloudError("登录已过期，请重新扫码。") }
        credentials.ssecurity=str(data["ssecurity"])
        try await follow(data)
        guard !credentials.serviceToken.isEmpty, !credentials.ssecurity.isEmpty else { throw CloudError("登录续期失败，请重新扫码。") }
        return credentials
    }
    func cancel() { network.reset() }
}
final class CloudClient {
    var auth: Credentials
    let network=Network(login:false)
    static let sceneList="/appgateway/miot/appsceneservice/AppSceneService/GetSimpleSceneList"
    static let sceneRun="/appgateway/miot/appsceneservice/AppSceneService/NewRunScene"
    init(_ auth: Credentials) { self.auth=auth }
    func request(_ path: String,_ payload: [String:Any]) async throws -> Any {
        let allowed=["/v2/homeroom/gethome_merged","/home/home_device_list","/miotspec/prop/get","/miotspec/prop/set",Self.sceneList,Self.sceneRun]
        guard allowed.contains(path), let security=Data(base64Encoded:auth.ssecurity), !security.isEmpty else { throw CloudError("未登录或接口不在支持范围。") }
        var random=[UInt8](repeating:0,count:8); guard SecRandomCopyBytes(kSecRandomDefault,8,&random) == errSecSuccess else { throw CloudError("无法生成安全请求随机数。") }
        let minute=UInt32(Date().timeIntervalSince1970/60)
        let nonce=Data(random+[UInt8((minute>>24)&255),UInt8((minute>>16)&255),UInt8((minute>>8)&255),UInt8(minute&255)])
        let key=Data(SHA256.hash(data:security+nonce)), signed=key.base64EncodedString()
        let body=try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys,.fragmentsAllowed])
        var pairs=[("data",String(decoding:body,as:UTF8.self))]
        pairs.append(("rc4_hash__",signature(path,pairs,signed)))
        pairs=pairs.map { ($0.0,rc4(key,Data($0.1.utf8)).base64EncodedString()) }
        pairs += [("signature",signature(path,pairs,signed)),("ssecurity",auth.ssecurity),("_nonce",nonce.base64EncodedString())]
        var r=URLRequest(url:URL(string:"https://api.mijia.tech/app"+path)!); r.httpMethod="POST"; r.httpBody=form(pairs)
        r.setValue(auth.ua,forHTTPHeaderField:"User-Agent"); r.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        r.setValue("ENCRYPT-RC4",forHTTPHeaderField:"MIOT-ENCRYPT-ALGORITHM"); r.setValue("PROTOCAL-HTTP2",forHTTPHeaderField:"x-xiaomi-protocal-flag-cli")
        r.setValue("userId=\(auth.userId);cUserId=\(auth.cUserId);serviceToken=\(auth.serviceToken);yetAnotherServiceToken=\(auth.serviceToken);locale=zh_CN;timezone_id=Asia/Shanghai;channel=MI_APP_STORE;PassportDeviceId=\(auth.deviceId)",forHTTPHeaderField:"Cookie")
        let bytes=try await network.fetch(r)
        let decoded: Data
        if (try? JSONSerialization.jsonObject(with:bytes)) != nil { decoded=bytes }
        else { guard let encoded=Data(base64Encoded:bytes,options:.ignoreUnknownCharacters) else { throw CloudError("小米云响应无法解析。") }; decoded=rc4(key,encoded) }
        let result=try json(decoded)
        guard result["code"] as? Int == 0 else { throw CloudError("小米云拒绝请求，code=\(str(result["code"]))。请刷新登录；控制命令不会自动重发。") }
        return result["result"] ?? [:]
    }
    func homes() async throws -> [CloudHome] {
        guard let result=try await request("/v2/homeroom/gethome_merged",["fg":true,"fetch_share":true,"fetch_share_dev":true,"fetch_cariot":true,"limit":300,"app_ver":7,"plat_form":0]) as? [String:Any], let rows=result["homelist"] as? [[String:Any]] else { throw CloudError("家庭目录响应格式不符。") }
        return rows.compactMap { let id=str($0["id"]), owner=str($0["uid"]); return id.isEmpty || Int64(owner) == nil ? nil : CloudHome(id:id,name:str($0["name"]),owner:owner) }
    }
}
