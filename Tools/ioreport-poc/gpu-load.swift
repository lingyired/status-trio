import Foundation
import Metal
let src = """
#include <metal_stdlib>
using namespace metal;
kernel void busy(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
  float x = float(id) * 0.000001f + 1.0f;
  for (int i = 0; i < 200000; ++i) { x = fma(x, 1.0000001f, 0.0000001f); }
  out[id % 1024] = x;
}
"""
guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue() else { print("no metal"); exit(1) }
let lib = try! dev.makeLibrary(source: src, options: nil)
let fn = lib.makeFunction(name: "busy")!
let pipe = try! dev.makeComputePipelineState(function: fn)
let buf = dev.makeBuffer(length: 4096, options: .storageModeShared)!
let secs = Double(CommandLine.arguments.dropFirst().first ?? "5") ?? 5
let deadline = Date().addingTimeInterval(secs)
let threads = dev.maxThreadsPerThreadgroup
while Date() < deadline {
  let cmd = q.makeCommandBuffer()!
  let enc = cmd.makeComputeCommandEncoder()!
  enc.setComputePipelineState(pipe); enc.setBuffer(buf, offset: 0, index: 0)
  let n = 262144
  enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: threads)
  enc.endEncoding(); cmd.commit(); cmd.waitUntilCompleted()
}
print("gpu load done \(secs)s")
