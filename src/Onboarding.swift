import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

func qrImage(_ content: String) -> NSImage? {
    let f=CIFilter.qrCodeGenerator(); f.message=Data(content.utf8); f.correctionLevel="M"
    guard let output=f.outputImage, let cg=CIContext().createCGImage(output.transformed(by:CGAffineTransform(scaleX:8,y:8)),from:output.extent.applying(CGAffineTransform(scaleX:8,y:8))) else { return nil }
    return NSImage(cgImage:cg,size:NSSize(width:260,height:260))
}
struct ShareRoot: View {
    @ObservedObject var model: HomeModel
    var showBar: ()->Void
    var body: some View {
        Group {
            if model.signedIn && model.backend != nil { HomeView(model:model,showBar:showBar) }
            else { AccountView(model:model,canClose:false) }
        }.sheet(isPresented:$model.showAccount) { AccountView(model:model,canClose:true).frame(width:760,height:620) }
    }
}
struct AccountView: View {
    @ObservedObject var model: HomeModel
    let canClose: Bool
    var body: some View {
        VStack(spacing:20) {
            HStack {
                Label("家控台",systemImage:"house.fill").font(.system(size:20,weight:.bold)).foregroundColor(Theme.mint)
                Spacer(); Text("HOME / DECK  ·  SHARE").font(.system(size:10,design:.monospaced)).tracking(2).foregroundColor(Theme.muted)
                if canClose { Button { model.showAccount=false } label: { Image(systemName:"xmark.circle.fill").font(.title2) } }
            }
            Spacer(minLength:0)
            if model.signedIn { homes } else { login }
            Spacer(minLength:0)
            Text("独立登录 · macOS 钥匙串保存 · 不读取电脑上的米家数据")
                .font(.system(size:11)).foregroundColor(Theme.muted)
        }.padding(36).frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(LinearGradient(colors:[Theme.canvas,Color(red:0.04,green:0.10,blue:0.14)],startPoint:.topLeading,endPoint:.bottomTrailing))
            .foregroundColor(.white).preferredColorScheme(.dark)
    }
    var login: some View {
        VStack(spacing:14) {
            Text("你的家，你的控制台。").font(.system(size:30,weight:.semibold))
            Text("用自己的米家账号登录，设备与场景自动发现。")
                .font(.system(size:13)).foregroundColor(Theme.muted)
            Group {
                if let content=model.qrContent, let image=qrImage(content) {
                    Image(nsImage:image).interpolation(.none).resizable().scaledToFit().frame(width:238,height:238).padding(14).background(Color.white).clipShape(RoundedRectangle(cornerRadius:16))
                } else {
                    ZStack { RoundedRectangle(cornerRadius:16).fill(Theme.card); Image(systemName:"qrcode.viewfinder").font(.system(size:82,weight:.ultraLight)).foregroundColor(Theme.mint.opacity(0.7)); if model.loginBusy { ProgressView().offset(y:75) } }.frame(width:266,height:266)
                }
            }.padding(.vertical,4)
            Text(model.loginStatus).font(.system(size:12)).multilineTextAlignment(.center).frame(maxWidth:480)
            HStack(spacing:12) {
                Button(model.loginBusy ? "刷新二维码" : "扫码登录") { model.beginLogin() }.buttonStyle(PillButton(tint:Theme.mint))
                if model.loginBusy { Button("取消") { model.cancelLogin() }.buttonStyle(PillButton(tint:.gray)) }
            }
            Text("服务地区：中国大陆　·　首次使用需联网")
                .font(.system(size:11)).foregroundColor(Theme.muted)
        }
    }
    var homes: some View {
        VStack(spacing:16) {
            Image(systemName:"house.and.flag.fill").font(.system(size:44)).foregroundColor(Theme.mint)
            Text("选择你的家庭").font(.system(size:28,weight:.semibold))
            Text(model.accountMessage).font(.system(size:12)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
            if model.busy { ProgressView().controlSize(.small) }
            ScrollView {
                VStack(spacing:8) {
                    ForEach(model.homes) { home in
                        Button { model.selectHome(home.id); model.showAccount=false } label: {
                            HStack { Image(systemName:home.id == model.homeID ? "checkmark.circle.fill" : "house"); Text(home.name); Spacer(); Image(systemName:"chevron.right") }.padding(18).foregroundColor(home.id == model.homeID ? Theme.mint : .white).panel()
                        }.buttonStyle(.plain).disabled(model.busy)
                    }
                }
            }.frame(maxWidth:480,maxHeight:220)
            HStack(spacing:12) {
                Button("重新读取家庭") { Task { await model.loadHomes() } }.buttonStyle(PillButton(tint:Theme.mint))
                Button("续期登录") { model.renewSession() }.buttonStyle(PillButton(tint:.cyan))
                Button("退出账号") { model.logout() }.buttonStyle(PillButton(tint:.orange))
            }.disabled(model.busy)
            Text("切换家庭会同步更新 Touch Bar，常用设备按账号和家庭分别保存。")
                .font(.system(size:11)).foregroundColor(Theme.muted)
        }
    }
}
