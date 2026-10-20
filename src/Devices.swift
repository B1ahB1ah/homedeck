import Foundation
import CoreFoundation

let labels=["on":"电源","brightness":"亮度","color-temperature":"色温","target-temperature":"目标温度","fan-level":"风速","mode":"模式"]
let translations=["Auto":"自动","Cool":"制冷","Dry":"除湿","Heat":"制热","Fan":"送风","Normal":"普通","Low":"低档","High":"高档","Reading":"阅读","Office":"办公","Leisure":"休闲","Warmth":"温馨","Computer":"电脑"]
func typeName(_ x: Any?) -> String { let s=str(x).split(separator:":"); return s.count > 3 ? String(s[3]) : "" }
struct DeviceRecord {
    var data: [String:Any]
    let did: String
    var id: String { str(data["id"]) }
    var controls: [[String:Any]] { (data["channels"] as? [[String:Any]] ?? []).flatMap { $0["controls"] as? [[String:Any]] ?? [] } }
}
func parseDevice(_ row: [String:Any],_ spec: [String:Any],_ uid: String) -> DeviceRecord? {
    let fullDid=str(row["did"]), model=str(row["model"])
    guard !fullDid.isEmpty else { return nil }
    let split=fullDid.range(of:#"\.s[0-9]+$"#,options:.regularExpression)
    let siid=split.flatMap { Int(fullDid[$0].dropFirst(2)) }
    let did=split.map { String(fullDid[..<$0.lowerBound]) } ?? fullDid
    var channels=[[String:Any]](), kind="light"
    for service in spec["services"] as? [[String:Any]] ?? [] {
        guard let sid=service["iid"] as? Int, siid == nil || siid == sid else { continue }
        let serviceKind=typeName(service["type"])
        guard ["light","switch","fan","air-conditioner","heater"].contains(serviceKind) else { continue }
        var controls=[[String:Any]]()
        for p in service["properties"] as? [[String:Any]] ?? [] {
            let name=typeName(p["type"]), access=p["access"] as? [String] ?? [], format=str(p["format"])
            guard let label=labels[name], let pid=p["iid"] as? Int, access.contains("read"), access.contains("write"), serviceKind != "switch" || name == "on", name != "on" || format == "bool" else { continue }
            let options=(p["value-list"] as? [[String:Any]] ?? []).compactMap { v -> [String:Any]? in
                guard let n=v["value"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
                let text=str(v["description"]); return ["value":n,"label":translations[text] ?? (text.isEmpty ? str(n) : text)]
            }
            var control: [String:Any]=["id":"\(sid).\(pid)","name":name,"label":label,"format":format,"options":options,"siid":sid,"piid":pid]
            if let range=p["value-range"] as? [Double], range.count == 3, range.allSatisfy(\.isFinite), range[2]>0, range[1]>=range[0] { control["range"]=range }
            if name != "on", options.isEmpty, control["range"] == nil { continue }
            controls.append(control)
        }
        if controls.contains(where:{ str($0["name"]) == "on" }) { kind=serviceKind; channels.append(["id":str(sid),"name":"通道\(channels.count+1)","controls":controls]) }
    }
    guard !channels.isEmpty else { return nil }
    if model.split(separator:".").dropFirst().first == "switch" { kind="switch" }
    let data: [String:Any]=["id":opaque(uid,fullDid),"name":str(row["name"]),"model":model,"kind":kind,"group":["fan","air-conditioner","heater"].contains(kind) ? "温控" : "灯光","channels":channels,"cachedOnline":(row["isOnline"] as? Bool ?? false)]
    return DeviceRecord(data:data,did:did)
}
func validatedValue(_ control: [String:Any],_ value: Any) throws -> Any {
    let name=str(control["name"])
    guard let n=value as? NSNumber else { throw CloudError("无效控制值。") }
    if name == "on" { guard CFGetTypeID(n) == CFBooleanGetTypeID() else { throw CloudError("电源值必须明确为开或关。") }; return n.boolValue }
    guard CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { throw CloudError("无效控制数值。") }
    var x=n.doubleValue
    let range=control["range"] as? [Double]
    if name == "brightness" {
        guard (1...100).contains(x), let r=range, r.count==3, r[2]>0 else { throw CloudError("亮度必须在 1–100% 之间。") }
        x=r[0]+(x-1)/99*(r[1]-r[0])
    } else if let options=control["options"] as? [[String:Any]], !options.isEmpty {
        guard options.contains(where:{ ($0["value"] as? Double) == x }) else { throw CloudError("设备不支持此选项。") }
    } else { guard let r=range, r.count==3, r[2]>0, (r[0]...r[1]).contains(x) else { throw CloudError("设置值超出设备支持范围。") } }
    if let r=range, r.count==3, r[2]>0 { x=min(r[1],max(r[0],r[0]+((x-r[0])/r[2]).rounded()*r[2])) }
    return ["float","double"].contains(str(control["format"])) ? x : x.rounded()
}
final class NativeBackend {
    let client: CloudClient
    var home: CloudHome
    var records=[DeviceRecord]()
    var sceneRows=[[String:Any]]()
    var specs=[String:[String:Any]]()
    var unsupported=[String]()
    let specNetwork=Network(login:false)
    init(auth: Credentials,home: CloudHome) { self.client=CloudClient(auth); self.home=home }
    func discover() async throws {
        var raw=[[String:Any]](), start="", seen=Set<String>()
        for _ in 0..<100 {
            let result=try await client.request("/home/home_device_list",["home_owner":Int64(home.owner)!,"home_id":Int64(home.id) ?? 0,"limit":200,"start_did":start,"get_split_device":true,"support_smart_home":true,"get_cariot_device":true,"get_third_device":true])
            guard let page=result as? [String:Any], let rows=page["device_info"] as? [[String:Any]] else { throw CloudError("设备目录响应格式不符。") }
            raw += rows
            let next=str(page["max_did"])
            if page["has_more"] as? Bool != true { break }
            guard !next.isEmpty, !seen.contains(next) else { throw CloudError("设备分页未完成，请刷新重试。") }
            seen.insert(next); start=next
            if seen.count == 100 { throw CloudError("设备目录过大，请缩小家庭范围。") }
        }
        var splitServices=[String:Set<Int>]()
        for row in raw {
            let did=str(row["did"])
            if let r=did.range(of:#"\.s[0-9]+$"#,options:.regularExpression), let sid=Int(did[r].dropFirst(2)) { splitServices[String(did[..<r.lowerBound]),default:[]].insert(sid) }
        }
        var found=[DeviceRecord](), unavailable=[String](), ids=Set<String>()
        for row in raw {
            let model=str(row["model"])
            guard ["light","switch","fan","airc","acpartner","heater"].contains(model.split(separator:".").dropFirst().first.map(String.init) ?? "") else { unavailable.append(str(row["name"])); continue }
            let urn=str(row["spec_type"] ?? row["urn"])
            guard urn.hasPrefix("urn:miot-spec-v2:device:") else { unavailable.append(str(row["name"])); continue }
            if specs[urn] == nil {
                var url=URLComponents(string:"https://miot-spec.org/miot-spec-v2/instance")!; url.queryItems=[URLQueryItem(name:"type",value:urn)]
                // Public specs only: no Xiaomi account cookies or authorization headers.
                do { specs[urn]=try json(await specNetwork.fetch(URLRequest(url:url.url!))) }
                catch { unavailable.append(str(row["name"])+"（规格获取失败）"); continue }
            }
            var spec=specs[urn] ?? [:]
            let covered=splitServices[str(row["did"])] ?? []
            if !covered.isEmpty { spec["services"]=(spec["services"] as? [[String:Any]] ?? []).filter { !covered.contains($0["iid"] as? Int ?? -1) } }
            if let d=parseDevice(row,spec,client.auth.userId), ids.insert(d.id).inserted { found.append(d) }
            else if covered.isEmpty { unavailable.append(str(row["name"])) }
        }
        records=found.sorted { str($0.data["name"]).localizedStandardCompare(str($1.data["name"])) == .orderedAscending }; unsupported=unavailable
    }
    func read(_ source: [DeviceRecord]) async throws -> [DeviceRecord] {
        var result=source
        for i in result.indices { result[i].data["state"]=[String:Any]() }
        let params=source.flatMap { d in d.controls.map { ["did":d.did,"siid":$0["siid"]!,"piid":$0["piid"]!] } }
        for offset in stride(from:0,to:params.count,by:50) {
            let batch=Array(params[offset..<min(offset+50,params.count)])
            guard let rows=try await client.request("/miotspec/prop/get",["datasource":1,"params":batch]) as? [[String:Any]] else { throw CloudError("设备状态响应格式不符。") }
            for row in rows {
                let key="\(str(row["siid"])).\(str(row["piid"]))"
                for i in result.indices where result[i].did == str(row["did"]) {
                    guard let p=result[i].controls.first(where:{str($0["id"]) == key}) else { continue }
                    var state=result[i].data["state"] as? [String:Any] ?? [:], item: [String:Any]=["code":row["code"] as? Int ?? -1]
                    if row["code"] as? Int == 0 {
                        if let n=row["value"] as? NSNumber {
                            if str(p["name"]) == "on" { if n.doubleValue == 0 || n.doubleValue == 1 { item["value"]=n.boolValue } else { item["code"] = -1 } }
                            else if CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite {
                                item["value"]=n
                                if str(p["name"]) == "brightness", let r=p["range"] as? [Double], r.count==3 { item["percent"]=r[1]>r[0] ? max(1,min(100,Int((1+(n.doubleValue-r[0])/(r[1]-r[0])*99).rounded()))) : 100 }
                            } else { item["code"] = -1 }
                        } else { item["code"] = -1 }
                    }
                    state[key]=item; result[i].data["state"]=state
                }
            }
        }
        return result
    }
    func actionLabel(_ action: [String:Any]) -> String {
        if let name=action["name"] as? String, !name.isEmpty { return name }
        var payload=action["payload_json"] as? [String:Any] ?? [:]
        if let s=action["payload_json"] as? String, let d=s.data(using:.utf8) { payload=(try? json(d)) ?? [:] }
        if str(payload["command"]) == "set_properties", let values=payload["value"] as? [[String:Any]] {
            let lines=values.compactMap { row -> String? in
                let key="\(str(row["siid"])).\(str(row["piid"]))"
                for d in records where d.did == str(row["did"]) {
                    guard let p=d.controls.first(where:{ str($0["id"]) == key }) else { continue }
                    let label: String
                    if str(p["name"]) == "on", let n=row["value"] as? NSNumber { label=n.boolValue ? "开启" : "关闭" }
                    else if let n=row["value"] as? Double {
                        if str(p["name"]) == "brightness", let r=p["range"] as? [Double], r.count==3, r[1]>r[0] { label="亮度 \(max(1,min(100,Int((1+(n-r[0])/(r[1]-r[0])*99).rounded()))))%" }
                        else { let option=(p["options"] as? [[String:Any]] ?? []).first { $0["value"] as? Double == n }; label=str(p["label"])+" "+(option.map { str($0["label"]) } ?? str(row["value"])) }
                    } else { label="按米家定义执行" }
                    return str(d.data["name"])+" · "+label
                }; return nil
            }
            if !lines.isEmpty { return lines.joined(separator:"；") }
        }
        if let nested=action["nested_scene_info"] as? [String:Any], let n=nested["name"] as? String { return "执行子场景 · "+n }
        return (payload["device_name"] as? String ?? "设备")+" · 按米家定义执行"
    }
    func scenes() async throws -> [[String:Any]] {
        guard let result=try await client.request(CloudClient.sceneList,["app_version":12,"get_type":2,"home_id":home.id,"owner_uid":Int64(home.owner)!]) as? [String:Any] else { throw CloudError("场景目录响应格式不符。") }
        sceneRows=result["manual_scene_info_list"] as? [[String:Any]] ?? []
        return sceneRows.compactMap { s in
            guard !str(s["scene_id"]).isEmpty, !str(s["name"]).isEmpty else { return nil }
            let actions=(s["scene_action"] as? [String:Any])?["actions"] as? [[String:Any]] ?? []
            return ["id":opaque(home.id,str(s["scene_id"])),"name":str(s["name"]),"enabled":(s["enable"] as? Bool ?? false) && (s["authed"] as? Bool ?? true),"actionCount":actions.count,"actionNames":actions.prefix(20).map(actionLabel)]
        }
    }
    func handle(_ command: [String:Any]) async throws -> Reply {
        var response: [String:Any]=["ok":true]
        switch str(command["action"]) {
        case "snapshot":
            try await discover(); records=try await read(records)
            response["devices"]=records.map(\.data); response["unsupported"]=unsupported
            do { response["scenes"]=try await scenes() } catch { response["scenes"]=[[String:Any]](); response["warnings"]=[error.localizedDescription] }
        case "set":
            guard let index=records.firstIndex(where:{$0.id == str(command["device"])}), let control=records[index].controls.first(where:{str($0["id"]) == str(command["control"])}), let raw=command["value"] else { throw CloudError("设备或属性不在当前家庭目录中，请刷新。") }
            let value=try validatedValue(control,raw), d=records[index]
            let params: [String:Any]=["did":d.did,"siid":control["siid"]!,"piid":control["piid"]!,"value":value]
            // Exactly one mutation request. No automatic retry, including authentication failures.
            guard let ack=try await client.request("/miotspec/prop/set",["params":[params]]) as? [[String:Any]], ack.count==1, str(ack[0]["did"]) == d.did, str(ack[0]["siid"]) == str(control["siid"]), str(ack[0]["piid"]) == str(control["piid"]), [0,1].contains(ack[0]["code"] as? Int ?? -1) else { throw CloudError("写入未确认；请先刷新状态，不自动重发。") }
            try? await Task.sleep(nanoseconds:700_000_000)
            var confirmed=false
            if let back=try? await read([d]), let fresh=back.first {
                records[index]=fresh
                if let state=fresh.data["state"] as? [String:[String:Any]], let property=state[str(control["id"])], property["code"] as? Int == 0, let n=property["value"] as? NSNumber, let target=value as? NSNumber { confirmed=n == target }
            }
            response["device"]=records[index].data; response["readbackConfirmed"]=confirmed; response["message"]=confirmed ? "设置已回读确认" : "指令已接受，回读尚未确认，请刷新状态。"
        case "scene":
            _=try await scenes()
            guard command["confirm"] as? Bool == true, let s=sceneRows.first(where:{opaque(home.id,str($0["scene_id"])) == str(command["scene"])}), s["enable"] as? Bool == true, s["authed"] as? Bool != false else { throw CloudError("场景不可用或尚未确认。") }
            _=try await client.request(CloudClient.sceneRun,["scene_id":str(s["scene_id"]),"scene_type":2,"phone_id":"null","home_id":home.id,"owner_uid":Int64(home.owner)!])
            response["message"]="场景已提交，请查看后续设备状态。"
        default: throw CloudError("不支持此操作。")
        }
        return try JSONDecoder().decode(Reply.self,from:JSONSerialization.data(withJSONObject:response))
    }
}
