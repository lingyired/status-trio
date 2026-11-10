#!/usr/bin/env swift
// Prints the AX frame of one app's status-bar menu item plus the main-screen
// backing scale, as JSON. Read-only; no windows or focus are touched.
//
// Usage: swift scripts/menubar-item-frame.swift <pid>
// Output: {"x":1340.0,"y":2.5,"w":42.0,"h":26.0,"mainScale":2.0,"screens":[{...}]}
import AppKit
import ApplicationServices

func attr(_ el: AXUIElement, _ n: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil
}
func point(_ v: AnyObject?) -> CGPoint? {
    guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero; AXValueGetValue(v as! AXValue, .cgPoint, &p); return p
}
func size(_ v: AnyObject?) -> CGSize? {
    guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero; AXValueGetValue(v as! AXValue, .cgSize, &s); return s
}

guard CommandLine.arguments.count >= 2, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: menubar-item-frame.swift <pid>\n".utf8))
    exit(2)
}
let app = AXUIElementCreateApplication(pid)

func find(_ el: AXUIElement, _ depth: Int) -> (CGPoint, CGSize)? {
    if depth > 8 { return nil }
    if (attr(el, kAXRoleAttribute) as? String) == "AXMenuBarItem",
       let p = point(attr(el, kAXPositionAttribute)),
       let s = size(attr(el, kAXSizeAttribute)) {
        return (p, s)
    }
    if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for k in kids { if let r = find(k, depth + 1) { return r } }
    }
    return nil
}

guard let (p, s) = find(app, 0) else {
    FileHandle.standardError.write(Data("no AXMenuBarItem found for pid \(pid)\n".utf8))
    exit(4)
}

let screens: [[String: Any]] = NSScreen.screens.map { sc in
    ["scale": sc.backingScaleFactor,
     "frame": [sc.frame.origin.x, sc.frame.origin.y, sc.frame.size.width, sc.frame.size.height]]
}
let record: [String: Any] = [
    "x": p.x, "y": p.y, "w": s.width, "h": s.height,
    "mainScale": NSScreen.main?.backingScaleFactor ?? 1,
    "screens": screens,
]
if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
    print(String(decoding: data, as: UTF8.self))
}
