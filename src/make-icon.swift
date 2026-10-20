import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
func drawIcon(_ size: Int) -> Data {
    let image = NSImage(size: NSSize(width:size,height:size))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    let rect = CGRect(x:32,y:32,width:960,height:960)
    let path = CGPath(roundedRect:rect,cornerWidth:220,cornerHeight:220,transform:nil)
    context.addPath(path); context.clip()
    let colors = [NSColor(red:0.14,green:0.20,blue:0.34,alpha:1).cgColor,NSColor(red:0.025,green:0.04,blue:0.09,alpha:1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,1])!
    context.drawLinearGradient(gradient,start:CGPoint(x:50,y:970),end:CGPoint(x:1000,y:10),options:[])
    for (x,y,r,c) in [(720.0,760.0,380.0,NSColor.systemTeal),(270.0,400.0,300.0,NSColor.systemIndigo)] {
        let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[c.withAlphaComponent(0.25).cgColor,c.withAlphaComponent(0).cgColor] as CFArray,locations:[0,1])!
        context.drawRadialGradient(g,startCenter:CGPoint(x:x,y:y),startRadius:0,endCenter:CGPoint(x:x,y:y),endRadius:r,options:[])
    }
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.94).cgColor)
    context.setLineWidth(48); context.setLineCap(.round); context.setLineJoin(.round)
    context.move(to:CGPoint(x:250,y:590));context.addLine(to:CGPoint(x:512,y:810));context.addLine(to:CGPoint(x:774,y:590));context.strokePath()
    context.move(to:CGPoint(x:310,y:600));context.addLine(to:CGPoint(x:310,y:440));context.addQuadCurve(to:CGPoint(x:350,y:400),control:CGPoint(x:310,y:400));context.addLine(to:CGPoint(x:674,y:400));context.addQuadCurve(to:CGPoint(x:714,y:440),control:CGPoint(x:714,y:400));context.addLine(to:CGPoint(x:714,y:600));context.strokePath()
    for i in 0..<3 {
        let box=CGRect(x:230+i*196,y:225,width:172,height:88)
        context.setShadow(offset:.zero,blur:28,color:[NSColor.systemMint,NSColor.systemCyan,NSColor.systemOrange][i].withAlphaComponent(0.6).cgColor)
        context.setFillColor([NSColor.systemMint,NSColor.systemCyan,NSColor.systemOrange][i].cgColor)
        context.addPath(CGPath(roundedRect:box,cornerWidth:28,cornerHeight:28,transform:nil));context.fillPath()
    }
    context.setShadow(offset:.zero,blur:0,color:nil)
    image.unlockFocus()
    let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
    return bitmap.representation(using:.png,properties:[:])!
}
for base in [16,32,128,256,512] {
    for scale in [1,2] {
        let name="icon_\(base)x\(base)"+(scale==2 ? "@2x" : "")+".png"
        try drawIcon(base*scale).write(to:URL(fileURLWithPath:folder).appendingPathComponent(name))
    }
}
