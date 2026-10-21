import SwiftUI
import AppKit

enum Theme {
    static let canvas = Color(red:0.035, green:0.047, blue:0.078)
    static let card = Color(red:0.075, green:0.093, blue:0.14)
    static let muted = Color(red:0.53, green:0.60, blue:0.71)
    static let mint = Color(red:0.39, green:0.94, blue:0.77)
}
extension View {
    func panel(_ color: Color = .white.opacity(0.07), radius: CGFloat = 18) -> some View {
        self.background(RoundedRectangle(cornerRadius:radius).fill(color)).overlay(RoundedRectangle(cornerRadius:radius).stroke(.white.opacity(0.07),lineWidth:1))
    }
}
struct PillButton: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size:13,weight:.semibold)).padding(.horizontal,18).padding(.vertical,10)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.38 : 0.18)))
            .foregroundColor(tint).opacity(configuration.isPressed ? 0.8 : 1)
    }
}
struct HomeView: View {
    @ObservedObject var model: HomeModel
    var showBar: () -> Void
    var body: some View {
        HStack(spacing:0) {
            sidebar.frame(width:166)
            Rectangle().fill(.white.opacity(0.06)).frame(width:1)
            VStack(alignment:.leading,spacing:20) {
                header
                HStack(alignment:.top,spacing:18) {
                    VStack(alignment:.leading,spacing:14) {
                        HStack {
                            Text(model.page.rawValue).font(.system(size:22,weight:.bold))
                            Text(model.page == .scenes ? "\(model.scenes.count) 个手动场景" : "\(model.filteredDevices.count) 个设备").font(.system(size:12)).foregroundColor(Theme.muted)
                            Spacer()
                            Image(systemName:"magnifyingglass").foregroundColor(Theme.muted)
                            TextField("查找",text:$model.query).textFieldStyle(.plain).frame(width:100)
                        }
                        ScrollView {
                            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                                if model.page == .scenes {
                                    ForEach(model.filteredScenes) { s in SceneTile(scene:s,selected:model.selectedSceneID == s.id) { model.selectScene(s) } }
                                } else {
                                    ForEach(model.filteredDevices) { d in DeviceTile(device:d,selected:model.selectedDeviceID == d.id,favorite:model.favorites.contains(d.id),syncStatus:model.pendingText(d.id),select:{model.selectDevice(d)},star:{model.toggleFavorite(d)}) }
                                }
                            }.padding(.bottom,4)
                            if model.page == .favorites && model.filteredDevices.isEmpty { Text("在设备卡片上点星标，加入常用。无需执行设备操作。").foregroundColor(Theme.muted).padding(30) }
                        }.scrollIndicators(.hidden)
                    }.frame(maxWidth:.infinity)
                    detail.frame(width:282)
                }.frame(maxHeight:.infinity)
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Text("TOUCH BAR").font(.system(size:10,weight:.bold,design:.rounded)).tracking(2).foregroundColor(Theme.muted)
                        Text("交互预览").font(.system(size:11)).foregroundColor(Theme.muted)
                        Spacer()
                        Button("展开实机 Touch Bar",action:showBar).font(.system(size:11,weight:.semibold)).foregroundColor(Theme.mint)
                    }
                    TouchPreview(model:model).padding(10).background(Color.black).clipShape(RoundedRectangle(cornerRadius:14))
                }
                HStack(spacing:7) {
                    if model.busy { ProgressView().controlSize(.mini) } else { Circle().fill(model.failed ? Color.orange : Theme.mint).frame(width:5,height:5) }
                    Text(model.message).lineLimit(2).font(.system(size:11)).foregroundColor(model.failed ? .orange : Theme.muted)
                    Spacer(minLength:8)
                    Text("云端状态 · \(model.lastUpdateText)").font(.system(size:10,design:.monospaced)).foregroundColor(Theme.muted)
                }.frame(minHeight:25)
            }.padding(24)
        }
        .background(LinearGradient(colors:[Theme.canvas,Color(red:0.04,green:0.065,blue:0.10)],startPoint:.topLeading,endPoint:.bottomTrailing))
        .preferredColorScheme(.dark).foregroundColor(.white).buttonStyle(.plain)
        .frame(minWidth:1060,minHeight:740)
    }
    var sidebar: some View {
        VStack(alignment:.leading,spacing:7) {
            if let icon = NSImage(named:NSImage.Name("AppIcon")) { Image(nsImage:icon).resizable().frame(width:52,height:52).padding(.bottom,8) }
            Text("家控台").font(.system(size:24,weight:.bold))
            Text("HOME / DECK").font(.system(size:9,weight:.medium,design:.monospaced)).tracking(2).foregroundColor(Theme.muted)
            Rectangle().fill(.white.opacity(0.08)).frame(height:1).padding(.vertical,22)
            ForEach(Page.allCases,id:\.self) { page in
                Button { model.changePage(page) } label: {
                    HStack(spacing:12) { Image(systemName:page.symbol).frame(width:20); Text(page.rawValue).fontWeight(.semibold); Spacer() }
                        .foregroundColor(model.page == page ? page.color : Theme.muted)
                        .padding(.horizontal,13).padding(.vertical,13)
                        .background(RoundedRectangle(cornerRadius:12).fill(model.page == page ? page.color.opacity(0.13) : .clear))
                }
            }
            Spacer()
            Button { model.showAccount=true } label: {
                VStack(alignment:.leading,spacing:5) {
                    Label(model.homeName,systemImage:"person.crop.circle")
                    Text("家庭与账号").font(.system(size:10)).foregroundColor(Theme.muted)
                }.font(.system(size:12)).foregroundColor(Theme.mint).padding(.bottom,16)
            }
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:6) { Circle().fill(model.globalAvailable ? Theme.mint : .orange).frame(width:5,height:5); Text(model.globalAvailable ? "全局入口已注册" : "菜单栏常驻").font(.system(size:10,weight:.medium)) }
                Text("关闭窗口后仍运行\n从菜单栏或 Touch Bar 唤出").font(.system(size:10)).lineSpacing(4).foregroundColor(Theme.muted)
                Text("v0.3.3 · 独立版").font(.system(size:9,design:.monospaced)).foregroundColor(Theme.muted.opacity(0.6)).padding(.top,7)
            }
        }.padding(.horizontal,18).padding(.vertical,24).background(Color.black.opacity(0.16))
    }
    var header: some View {
        HStack(alignment:.center) {
            VStack(alignment:.leading,spacing:5) {
                Text("让家，触手可及。").font(.system(size:25,weight:.semibold))
                Text("设备与场景，各就其位。点选预览，再明确执行。").font(.system(size:11)).foregroundColor(Theme.muted)
            }
            Spacer()
            VStack(alignment:.trailing,spacing:6) {
                HStack(spacing:15) {
                    Text("\(model.devices.count) 设备"); Text("\(model.scenes.count) 场景"); Text("\(model.activeCount) 开启").foregroundColor(Theme.mint)
                }.font(.system(size:11,weight:.medium,design:.rounded))
                Text("\(model.readableCount) 个电源状态可读 · 前台10秒 / 后台60秒刷新").font(.system(size:10)).foregroundColor(Theme.muted)
            }
            Button { model.refresh() } label: { Image(systemName:"arrow.clockwise").font(.system(size:16,weight:.medium)).frame(width:36,height:36).panel(.white.opacity(0.06),radius:12) }.disabled(model.busy).padding(.leading,8)
        }
    }
    @ViewBuilder var detail: some View {
        if model.page == .scenes, let scene = model.selectedScene { SceneDetail(scene:scene,model:model) }
        else if model.page == .scenes { EmptyDetail(symbol:"sparkles",title:"你的生活，一触切换",text:"点选场景查看动作清单，\n确认后才会执行。") }
        else if let device = model.selectedDevice { DeviceDetail(device:device,model:model) }
        else { EmptyDetail(symbol:"hand.tap",title:"选择一个设备",text:"点选卡片进入控制，\n不会直接切换设备。") }
    }
}
struct DeviceTile: View {
    let device: Device; let selected, favorite: Bool
    var syncStatus: String? = nil
    var select: () -> Void; var star: () -> Void
    var tint: Color { device.group == "温控" ? .cyan : .orange }
    var body: some View {
        ZStack(alignment:.topTrailing) {
            Button(action:select) {
                VStack(alignment:.leading,spacing:11) {
                    HStack { Image(systemName:device.symbol).font(.system(size:22)).foregroundColor(device.power == true ? tint : Theme.muted); Spacer() }
                    Text(device.name).font(.system(size:14,weight:.semibold)).lineLimit(1)
                    HStack(spacing:5) {
                        Circle().fill(device.power == nil ? Color.orange : device.power == true ? Theme.mint : Theme.muted.opacity(0.55)).frame(width:4,height:4)
                        Text(syncStatus != nil ? "待云端确认…" : device.power == nil ? "状态未确认" : device.power == true ? "已开启" : "已关闭").font(.system(size:10)).foregroundColor(Theme.muted)
                        Spacer()
                        if let brightness = device.controls.first(where: { $0.name == "brightness" }), device.numeric(brightness) != nil { Text(device.display(brightness)).font(.system(size:10,design:.monospaced)).foregroundColor(Theme.muted) }
                    }
                }.padding(15).frame(maxWidth:.infinity,alignment:.leading).frame(height:112)
                    .panel(selected ? tint.opacity(0.10) : Theme.card,radius:16)
                    .overlay(RoundedRectangle(cornerRadius:16).stroke(selected ? tint.opacity(0.5) : .clear,lineWidth:1))
            }
            Button(action:star) { Image(systemName:favorite ? "star.fill" : "star").font(.system(size:11)).foregroundColor(favorite ? Theme.mint : Theme.muted.opacity(0.7)).padding(14) }.help(favorite ? "移出常用" : "加入常用")
        }
    }
}
struct SceneTile: View {
    let scene: Scene; let selected: Bool; var select: () -> Void
    var body: some View {
        Button(action:select) {
            VStack(alignment:.leading,spacing:11) {
                HStack { Image(systemName:scene.symbol).font(.system(size:22)).foregroundColor(.purple); Spacer(); Image(systemName:"chevron.right").font(.system(size:9)).foregroundColor(Theme.muted) }
                Text(scene.name).font(.system(size:14,weight:.semibold)).lineLimit(1)
                Text(scene.enabled ? "\(scene.actionCount) 个动作 · 点击预览" : "米家中不可执行").font(.system(size:10)).foregroundColor(Theme.muted)
            }.padding(15).frame(maxWidth:.infinity,alignment:.leading).frame(height:112)
                .panel(selected ? Color.purple.opacity(0.14) : Theme.card,radius:16)
                .overlay(RoundedRectangle(cornerRadius:16).stroke(selected ? Color.purple.opacity(0.6) : .clear,lineWidth:1)).opacity(scene.enabled ? 1 : 0.5)
        }
    }
}
struct EmptyDetail: View {
    let symbol,title,text: String
    var body: some View { VStack(spacing:16) { Spacer(); Image(systemName:symbol).font(.system(size:38,weight:.light)).foregroundColor(Theme.muted); Text(title).font(.system(size:16,weight:.semibold)); Text(text).font(.system(size:11)).lineSpacing(5).multilineTextAlignment(.center).foregroundColor(Theme.muted); Spacer() }.frame(maxWidth:.infinity).frame(height:430).panel(Theme.card) }
}
struct DeviceDetail: View {
    let device: Device
    @ObservedObject var model: HomeModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:17) {
                HStack {
                    Image(systemName:device.symbol).font(.system(size:27)).foregroundColor(device.group == "温控" ? .cyan : .orange)
                    Spacer()
                    Text(device.group).font(.system(size:10,weight:.semibold)).foregroundColor(Theme.muted).padding(7).panel(.white.opacity(0.04),radius:8)
                }
                Text(device.name).font(.system(size:21,weight:.bold))
                HStack(spacing:7) { Circle().fill(device.power == true ? Theme.mint : Theme.muted).frame(width:6,height:6); Text(device.power == nil ? "状态未确认" : device.power == true ? "已开启" : "已关闭").font(.system(size:12)).foregroundColor(Theme.muted) }
                if let power = device.powerControl {
                    HStack(spacing:10) {
                        Button { model.set(device,power,true) } label: { Label("开启",systemImage:"power") }.buttonStyle(PillButton(tint:Theme.mint))
                        Button { model.set(device,power,false) } label: { Text("关闭") }.buttonStyle(PillButton(tint:.white.opacity(0.75)))
                    }.disabled(model.busy || device.power == nil)
                }
                if let status=model.pendingText(device.id) { Label(status,systemImage:"clock.arrow.circlepath").font(.system(size:11)).foregroundColor(.orange) }
                Divider().overlay(.white.opacity(0.05))
                ForEach(["主要控制","更多控制","环境状态"],id:\.self) { section in
                    let controls=device.controls.filter { $0.name != "on" && ($0.section ?? "主要控制") == section }
                    if !controls.isEmpty {
                        Text(section).font(.system(size:10,weight:.bold)).foregroundColor(Theme.muted).padding(.top,5)
                        ForEach(controls) { control in ControlEditor(device:device,control:control,model:model).id(device.id+"/"+control.id) }
                    }
                }
                if device.controls.count == 1 { Text("此设备提供明确的开／关控制。").font(.system(size:11)).foregroundColor(Theme.muted).padding(.vertical,10) }
                Spacer(minLength:8)
                Text(device.model).font(.system(size:9,design:.monospaced)).foregroundColor(Theme.muted.opacity(0.6)).textSelection(.enabled)
                Text("操作后持续查询状态；显示云端回读结果。").font(.system(size:10)).lineSpacing(4).foregroundColor(Theme.muted)
            }.padding(20)
        }.scrollIndicators(.hidden).panel(Theme.card)
    }
}
struct ControlEditor: View {
    let device: Device, control: Control
    @ObservedObject var model: HomeModel
    @State var draft: Double = 1
    @State var editing = false
    var limits: ClosedRange<Double> { if control.name == "brightness" { return 1...100 }; if let r = control.range, r.count >= 2, r[0] < r[1] { return r[0]...r[1] }; return 0...1 }
    var step: Double { control.name == "brightness" ? 1 : control.range?.last ?? 1 }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text(control.label).font(.system(size:12,weight:.medium)); Spacer(); Text(editing ? String(format:"%g",draft)+control.unit : device.display(control)).font(.system(size:11,design:.monospaced)).foregroundColor(Theme.muted) }
            if !control.isWritable {
                EmptyView()
            } else if control.format == "bool" {
                HStack(spacing:10) {
                    Button("开启") { model.set(device,control,true) }.buttonStyle(PillButton(tint:device.boolean(control) == true ? Theme.mint : .gray))
                    Button("关闭") { model.set(device,control,false) }.buttonStyle(PillButton(tint:device.boolean(control) == false ? .cyan : .gray))
                }
            } else if !control.options.isEmpty {
                Picker("",selection:Binding(get:{device.numeric(control) ?? -999},set:{model.set(device,control,$0)})) {
                    if device.numeric(control) == nil { Text("未确认").tag(-999.0) }
                    ForEach(control.options,id:\.value) { option in Text(option.label).tag(option.value) }
                }.labelsHidden().pickerStyle(.menu)
            } else if control.range != nil {
                if control.name == "off-delay-time" {
                    HStack(spacing:8) {
                        ForEach([0,30,60,120],id:\.self) { minutes in
                            if limits.contains(Double(minutes)) {
                                Button(minutes == 0 ? "取消" : minutes<60 ? "30分" : "\(minutes/60)时") { model.set(device,control,Double(minutes)) }.buttonStyle(PillButton(tint:.cyan))
                            }
                        }
                    }
                }
                if control.name == "target-temperature" {
                    HStack {
                        Button { model.set(device,control,max(limits.lowerBound,(device.numeric(control) ?? draft)-step)) } label: { Image(systemName:"minus.circle.fill").font(.title2) }
                        Spacer(); Text(device.display(control)).font(.system(size:24,weight:.medium,design:.rounded)).foregroundColor(Theme.mint); Spacer()
                        Button { model.set(device,control,min(limits.upperBound,(device.numeric(control) ?? draft)+step)) } label: { Image(systemName:"plus.circle.fill").font(.title2) }
                    }.padding(.vertical,5)
                }
                Slider(value:$draft,in:limits,step:step,onEditingChanged:{ active in editing=active; if !active { model.set(device,control,draft) } }).tint(control.name == "color-temperature" ? .orange : Theme.mint)
                HStack { Text(String(format:"%g",limits.lowerBound)); Spacer(); Text(String(format:"%g",limits.upperBound)+control.unit) }.font(.system(size:9,design:.monospaced)).foregroundColor(Theme.muted)
            }
        }.disabled(model.busy || (control.format == "bool" ? device.boolean(control) == nil : device.numeric(control) == nil))
            .onAppear { draft = min(limits.upperBound,max(limits.lowerBound,device.numeric(control) ?? limits.lowerBound)) }
            .onChange(of:device.numeric(control)) { value in if !editing { draft = min(limits.upperBound,max(limits.lowerBound,value ?? limits.lowerBound)) } }
            .padding(.bottom,4)
    }
}
struct SceneDetail: View {
    let scene: Scene
    @ObservedObject var model: HomeModel
    @State var confirm = false
    var body: some View {
        VStack(alignment:.leading,spacing:17) {
            Image(systemName:scene.symbol).font(.system(size:34,weight:.light)).foregroundColor(.purple)
            Text(scene.name).font(.system(size:23,weight:.bold))
            Text("包含 \(scene.actionCount) 个动作").font(.system(size:12)).foregroundColor(Theme.muted)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(Array(scene.actionNames.enumerated()),id:\.offset) { index, name in HStack(alignment:.top,spacing:8) { Text(String(format:"%02d",index+1)).font(.system(size:10,design:.monospaced)).foregroundColor(.purple); Text(name).font(.system(size:11)).foregroundColor(Theme.muted) } }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.frame(maxHeight:200)
            Text("按米家当前场景定义执行，可能影响多个设备。").font(.system(size:10)).foregroundColor(Theme.muted).lineSpacing(4)
            Button { confirm = true } label: { Label("执行场景",systemImage:"play.fill").frame(maxWidth:.infinity) }.buttonStyle(PillButton(tint:.purple)).disabled(model.busy || !scene.enabled)
            if !scene.enabled { Text("此场景当前未启用或未授权").font(.system(size:10)).foregroundColor(.orange) }
            Spacer(minLength:0)
        }.padding(20).panel(Theme.card)
        .alert("执行“\(scene.name)”？",isPresented:$confirm) {
            Button("取消",role:.cancel) { }
            Button("确认执行") { model.runScene(scene) }
        } message: { Text("米家场景包含\(scene.actionCount)个动作。提交后不自动重复执行。") }
    }
}
struct TouchPreview: View {
    @ObservedObject var model: HomeModel
    func chip(_ title: String,_ color: Color = .gray,_ action: @escaping () -> Void) -> some View {
        Button(action:action) { Text(title).font(.system(size:11,weight:.medium)).lineLimit(1).padding(.horizontal,12).frame(height:29).background(RoundedRectangle(cornerRadius:7).fill(color.opacity(0.24))).foregroundColor(color == .gray ? .white : color) }
    }
    var body: some View {
        HStack(spacing:6) {
            Image(systemName:"house.fill").font(.system(size:14)).foregroundColor(Theme.mint).frame(width:25)
            if model.touchMode == .overview {
                ForEach(Page.allCases,id:\.self) { p in Button { model.changePage(p) } label: { Image(systemName:p.symbol).font(.system(size:12)).frame(width:29,height:29).background(RoundedRectangle(cornerRadius:7).fill(model.page == p ? p.color.opacity(0.25) : .white.opacity(0.08))).foregroundColor(p.color) } }
                Rectangle().fill(.white.opacity(0.15)).frame(width:1,height:18).padding(.horizontal,4)
                if model.page == .scenes { ForEach(model.filteredScenes.prefix(4)) { s in chip(s.name,.purple) {model.selectScene(s)} } }
                else { ForEach(model.filteredDevices.prefix(4)) { d in chip((d.power == true ? "● " : "○ ")+d.shortName,model.page.color) {model.selectDevice(d)} } }
                Spacer(minLength:0)
                Image(systemName:"chevron.right").foregroundColor(Theme.muted).font(.system(size:10))
            } else if model.touchMode == .device, let d = model.selectedDevice {
                chip("‹ 返回",.gray) {model.back()}
                Text(d.shortName).font(.system(size:12,weight:.semibold)).padding(.horizontal,5)
                Text(d.power == nil ? "未确认" : d.power == true ? "已开启" : "已关闭").font(.system(size:10)).foregroundColor(Theme.muted)
                Spacer()
                Text("明确开／关").font(.system(size:10)).foregroundColor(Theme.mint)
                if let c = d.controls.first(where:{$0.name != "on" && $0.isWritable}) { chip("\(c.label) \(d.display(c))",model.page.color) { } }
            } else if let s = model.selectedScene {
                chip("‹ 返回",.gray) {model.back()}; Text(s.name).font(.system(size:12,weight:.semibold)); Text("\(s.actionCount)个动作").font(.system(size:10)).foregroundColor(Theme.muted); Spacer(); Text("实机上再次点击“确认执行”").font(.system(size:10)).foregroundColor(.purple)
            }
        }.frame(height:30)
    }
}
