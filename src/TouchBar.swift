import AppKit

final class HomeTouch: NSObject, NSTouchBarDelegate, NSScrubberDataSource, NSScrubberDelegate {
    let model: HomeModel
    let bar = NSTouchBar()
    let trayID = NSTouchBarItem.Identifier("app.homedeck.share.tray")
    let contentID = NSTouchBarItem.Identifier("app.homedeck.share.content")
    var tray: NSCustomTouchBarItem!
    var content: NSCustomTouchBarItem?
    var visible = false
    var scrubber: NSScrubber?
    var changeControl: Control?
    var selectedOptions: [Choice] = []
    init(model: HomeModel) {
        self.model = model; super.init()
        bar.delegate = self
        bar.defaultItemIdentifiers = [contentID]
        bar.principalItemIdentifier = contentID
        tray = NSCustomTouchBarItem(identifier:trayID)
        let button = NSButton(image:NSImage(systemSymbolName:"house.fill",accessibilityDescription:"家控台")!,target:self,action:#selector(show))
        button.contentTintColor = .systemMint
        tray.view = button
        model.globalAvailable = HDInstallTray(tray)
    }
    deinit { HDRemoveTray(tray) }
    @objc func show() {
        update()
        visible = HDShowBar(bar,trayID.rawValue)
        if let t = model.lastUpdate, Date().timeIntervalSince(t) > 20 { model.refresh() }
        report()
    }
    @objc func close() { HDHideBar(bar); visible = false; report() }
    @objc func back() { model.back() }
    @objc func page(_ sender: NSButton) { model.changePage(Page.allCases[sender.tag]) }
    @objc func refresh() { model.refresh() }
    @objc func powerOn() { if let d = model.selectedDevice, let c = d.powerControl { model.set(d,c,true) } }
    @objc func powerOff() { if let d = model.selectedDevice, let c = d.powerControl { model.set(d,c,false) } }
    @objc func cycleControl() {
        guard let d = model.selectedDevice else { return }
        let controls = d.controls.filter { $0.name != "on" }
        guard !controls.isEmpty else { return }
        let i = controls.firstIndex { $0.id == model.touchControlID } ?? -1
        model.touchControlID = controls[(i+1)%controls.count].id
        update()
    }
    @objc func slider(_ sender: NSSlider) { if let d = model.selectedDevice, let c = changeControl { model.set(d,c,sender.doubleValue) } }
    @objc func option(_ sender: NSSegmentedControl) {
        let i = sender.selectedSegment
        if let d = model.selectedDevice, let c = changeControl, selectedOptions.indices.contains(i) { model.set(d,c,selectedOptions[i].value) }
    }
    @objc func confirmScene() { if let s = model.selectedScene { model.runScene(s) } }
    func report() {
        let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!.appendingPathComponent("HomeDeckShare")
        try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let obj: [String:Any] = ["trayRegistered":model.globalAvailable,"presentationRequested":visible,"devices":model.devices.count,"scenes":model.scenes.count,"busy":model.busy,"page":model.page.rawValue,"date":ISO8601DateFormatter().string(from:Date())]
        if let data = try? JSONSerialization.data(withJSONObject:obj,options:.prettyPrinted) { try? data.write(to:root.appendingPathComponent("diagnostics.json"),options:.atomic) }
    }
    func touchBar(_ touchBar: NSTouchBar,makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == contentID else { return nil }
        content = NSCustomTouchBarItem(identifier:identifier)
        update(); return content
    }
    func button(_ title: String, _ action: Selector, tint: NSColor = .darkGray, width: CGFloat = 48) -> NSButton {
        let b = NSButton(title:title,target:self,action:action)
        b.bezelColor = tint
        b.widthAnchor.constraint(equalToConstant:width).isActive = true
        return b
    }
    func text(_ title: String,width: CGFloat, color:NSColor = .white) -> NSTextField {
        let t = NSTextField(labelWithString:title); t.textColor = color
        t.font = .systemFont(ofSize:12,weight:.medium)
        t.lineBreakMode = .byTruncatingTail
        t.widthAnchor.constraint(equalToConstant:width).isActive = true
        return t
    }
    func update() {
        report()
        guard let item = content else { return }
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 7; row.alignment = .centerY
        row.addArrangedSubview(button("×",#selector(close),width:30))
        switch model.touchMode {
        case .overview:
            for (index,page) in Page.allCases.enumerated() {
                let b = button(page.rawValue,#selector(self.page(_:)),tint:model.page == page ? page.nsColor.withAlphaComponent(0.5) : .darkGray,width:49)
                b.tag = index; row.addArrangedSubview(b)
            }
            let s = NSScrubber(frame:NSRect(x:0,y:0,width:637,height:30))
            s.register(NSScrubberTextItemView.self,forItemIdentifier:NSUserInterfaceItemIdentifier("chip"))
            let layout = NSScrubberFlowLayout(); layout.itemSize = NSSize(width:116,height:30); layout.itemSpacing = 6
            s.scrubberLayout = layout; s.mode = .free; s.dataSource = self; s.delegate = self
            s.showsArrowButtons = true
            s.selectionBackgroundStyle = .roundedBackground
            s.widthAnchor.constraint(equalToConstant:637).isActive = true
            scrubber = s; row.addArrangedSubview(s)
            row.addArrangedSubview(button("↻",#selector(refresh),width:35))
        case .device:
            row.addArrangedSubview(button("‹",#selector(back),width:35))
            if let d = model.selectedDevice {
                row.addArrangedSubview(text(d.shortName,width:112,color:d.group == "温控" ? .systemCyan : .systemOrange))
                row.addArrangedSubview(text(d.power == nil ? "未确认" : d.power == true ? "已开" : "已关",width:45,color:.lightGray))
                let on = button("开启",#selector(powerOn),tint:.systemGreen,width:64)
                let off = button("关闭",#selector(powerOff),width:64)
                on.isEnabled = !model.busy && d.power != nil; off.isEnabled = on.isEnabled
                row.addArrangedSubview(on); row.addArrangedSubview(off)
                let controls = d.controls.filter { $0.name != "on" }
                if let c = controls.first(where: { $0.id == model.touchControlID }) ?? controls.first {
                    changeControl = c
                    let selector = button(c.label + (controls.count > 1 ? " ⇄" : ""),#selector(cycleControl),width:80)
                    selector.isEnabled = !model.busy; row.addArrangedSubview(selector)
                    if !c.options.isEmpty {
                        selectedOptions = c.options
                        let segments = NSSegmentedControl(labels:c.options.map(\.label),trackingMode:.selectOne,target:self,action:#selector(option(_:)))
                        segments.selectedSegment = c.options.firstIndex { $0.value == d.numeric(c) } ?? -1
                        segments.widthAnchor.constraint(equalToConstant:260).isActive = true
                        segments.isEnabled = !model.busy && d.numeric(c) != nil
                        row.addArrangedSubview(segments)
                    } else if let r = c.range, r.count >= 2 {
                        let low = c.name == "brightness" ? 1 : r[0], high = c.name == "brightness" ? 100 : r[1]
                        let slide = NSSlider(value:d.numeric(c) ?? low,minValue:low,maxValue:high,target:self,action:#selector(slider(_:)))
                        slide.isContinuous = false; slide.isEnabled = !model.busy && d.numeric(c) != nil
                        slide.widthAnchor.constraint(equalToConstant:233).isActive = true
                        row.addArrangedSubview(slide)
                    }
                    row.addArrangedSubview(text(d.display(c),width:72,color:.lightGray))
                }
                row.addArrangedSubview(text(model.busy ? "等待回读…" : "",width:95,color:.systemMint))
            }
        case .scene:
            row.addArrangedSubview(button("‹",#selector(back),width:35))
            if let s = model.selectedScene {
                row.addArrangedSubview(text(s.name,width:148,color:.systemPurple))
                row.addArrangedSubview(text("\(s.actionCount) 个动作 · 可能影响多个设备",width:260,color:.lightGray))
                let execute = button(model.busy ? "提交中…" : "确认执行",#selector(confirmScene),tint:.systemPurple,width:110)
                execute.isEnabled = s.enabled && !model.busy; row.addArrangedSubview(execute)
                row.addArrangedSubview(text("不自动重试",width:100,color:.lightGray))
            }
        }
        row.widthAnchor.constraint(equalToConstant:950).isActive = true
        row.heightAnchor.constraint(equalToConstant:30).isActive = true
        item.view = row
    }
    func numberOfItems(for scrubber: NSScrubber) -> Int { model.page == .scenes ? model.filteredScenes.count : model.filteredDevices.count }
    func scrubber(_ scrubber: NSScrubber,viewForItemAt index: Int) -> NSScrubberItemView {
        let view = scrubber.makeItem(withIdentifier:NSUserInterfaceItemIdentifier("chip"),owner:nil) as! NSScrubberTextItemView
        if model.page == .scenes {
            let s = model.filteredScenes[index]; view.textField.stringValue = "✦ " + s.name
            view.textField.textColor = s.enabled ? .systemPurple : .gray
        } else {
            let d = model.filteredDevices[index]; view.textField.stringValue = (d.power == true ? "● " : d.power == nil ? "? " : "○ ") + d.shortName
            view.textField.textColor = d.power == true ? model.page.nsColor : .lightGray
        }
        view.textField.font = .systemFont(ofSize:12,weight:.medium)
        return view
    }
    func scrubber(_ scrubber: NSScrubber,didSelectItemAt index: Int) {
        if model.page == .scenes { let a = model.filteredScenes; if a.indices.contains(index) {model.selectScene(a[index])} }
        else { let a = model.filteredDevices; if a.indices.contains(index) {model.selectDevice(a[index])} }
    }
}
