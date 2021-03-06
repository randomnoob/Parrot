import AppKit
import Mocha

public extension NSWindow {
    public func scale(to scale: Double = 1.0, by anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        let p = anchorPoint
        assert((p.x >= 0.0 && p.x <= 1.0) && (p.y >= 0.0 && p.y <= 1.0),
               "Anchor point coordinates must be between 0 and 1!")
        let q = CGPoint(x: p.x * self.frame.size.width,
                        y: p.y * self.frame.size.height)
        let val = CGFloat(1.0 / scale).defaulting(0.0)
        
        // Apply the transformation by transparently using CGSSetWindowTransformAtPlacement()
        let a = CGAffineTransform(scaleX: val, y: val)
        self._private._setTransformForAnimation(a, anchorPoint: q)
    }
}

/*
DispatchQueue.main.async {
    var perspective = CATransform3DIdentity
    perspective.m34 = 1 / 500
    perspective = CATransform3DRotate(perspective, .pi * 0.4, 1, 0, 0)
    window.transform = perspective
}
*/
public extension NSWindow {
    public var transform: CATransform3D {
        get { return CATransform3DIdentity }
        set {
            let t = CATransform3DConcat(newValue, CATransform3DMakeScale(1, -1, 1))
            let f = self.frame
            let p = CGPoint(x: self.frame.minX, y: self.screen!.frame.height - self.frame.maxY)
            let w = Float(f.width), h = Float(f.height)
            
            let bl = CGSWarpPoint(local: CGSMeshPoint(x: 0, y: 0),
                                  global: CAMesh(CGSMeshPoint(x: 0, y: h), f, p, t))
            let br = CGSWarpPoint(local: CGSMeshPoint(x: w, y: 0),
                                  global: CAMesh(CGSMeshPoint(x: w, y: h), f, p, t))
            let tl = CGSWarpPoint(local: CGSMeshPoint(x: 0, y: h),
                                  global: CAMesh(CGSMeshPoint(x: 0, y: 0), f, p, t))
            let tr = CGSWarpPoint(local: CGSMeshPoint(x: w, y: h),
                                  global: CAMesh(CGSMeshPoint(x: w, y: 0), f, p, t))
            
            let warps = [bl, br, tl, tr]
            let ptr: UnsafeMutablePointer<CGSWarpPoint> = UnsafeMutablePointer(mutating: warps)
            _ = ptr.withMemoryRebound(to: CGSWarpPoint.self, capacity: 4) {
                CGSSetWindowWarp(NSApp.value(forKey: "contextID") as! Int32,
                                 CGWindowID(self.windowNumber), 2, 2, $0)
            }
        }
    }
}

/// CGError CGSSetWindowWarp(CGSConnectionID cid, CGWindowID wid, int width, int height, const CGSWarpPoint *warp);
@_silgen_name("CGSSetWindowWarp")
private func CGSSetWindowWarp(_ cid: Int32, _ wid: CGWindowID, _ width: Int, _ height: Int, _ warp: UnsafeRawPointer) -> Int32
private typealias CGSMeshPoint = (x: Float, y: Float)
private typealias CGSWarpPoint = (local: CGSMeshPoint, global: CGSMeshPoint)
private let _layers: (parent: CALayer, child: CALayer) = {
    let layer = CALayer()
    let sublayer = CALayer()
    layer.addSublayer(sublayer)
    return (layer, sublayer)
}()
private func CAPointApplyCATransform3D(_ transform: CATransform3D, _ frame: CGRect, _ point: CGPoint) -> CGPoint {
    objc_sync_enter(_layers.parent)
    defer { objc_sync_exit(_layers.parent) }
    
    //_layers.parent.anchorPoint = .zero
    //_layers.child.anchorPoint = .zero
    _layers.parent.frame = frame
    _layers.parent.sublayerTransform = transform
    return _layers.child.convert(point, to: _layers.parent)
}
private func CAMesh(_ m: CGSMeshPoint, _ f: CGRect, _ o: CGPoint, _ t: CATransform3D) -> CGSMeshPoint {
    let n = CAPointApplyCATransform3D(t, f, CGPoint(x: Double(m.x), y: Double(m.y)))
    return CGSMeshPoint(x: Float(n.x + o.x), y: Float(n.y + o.y))
}
