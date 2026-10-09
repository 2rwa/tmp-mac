import Foundation
import Metal
print("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
let ds = MTLCopyAllDevices()
print("MTL devices: \(ds.count)")
if let d = MTLCreateSystemDefaultDevice() {
    print("Default: \(d.name), lowPower: \(d.isLowPower), removable: \(d.isRemovable)")
    if let queue = d.makeCommandQueue(), let cmd = queue.makeCommandBuffer() {
        cmd.commit()
        cmd.waitUntilCompleted()
        print("Command status: \(cmd.status.rawValue), error: \(String(describing: cmd.error))")
    }
} else { print("No default Metal device exposed to the runner") }
for d in ds { print("Found: \(d.name)") }
