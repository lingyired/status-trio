#!/usr/bin/env swift
// Posts one alignment-fixture switch to a running Debug Status Trio instance via
// a process-scoped DistributedNotification. No settings or system state change.
//
// Usage: swift scripts/post-alignment-request.swift <bundle-id> <pid> <scenario:isolation:size>
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: post-alignment-request.swift <bundle-id> <pid> <fixture>\n".utf8))
    exit(2)
}
let name = Notification.Name("\(args[0]).alignment.\(args[1])")
DistributedNotificationCenter.default().postNotificationName(
    name, object: nil, userInfo: ["fixture": args[2]], deliverImmediately: true)
