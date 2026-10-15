import Darwin
import Foundation

func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardOutput.write(Data("[\(timestamp)] \(message)\n".utf8))
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

func fixedString<T>(_ value: T) -> String {
    var copy = value
    return withUnsafePointer(to: &copy) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { chars in
            String(cString: chars)
        }
    }
}

struct MountPoint {
    let device: String
    let mountPoint: String
    let fsType: String
}

func listMounts() -> [MountPoint] {
    let count = getfsstat(nil, 0, MNT_NOWAIT)
    guard count > 0 else { return [] }
    let buffer = UnsafeMutablePointer<statfs>.allocate(capacity: Int(count))
    defer { buffer.deallocate() }
    let bytes = Int32(Int(count) * MemoryLayout<statfs>.size)
    let used = getfsstat(buffer, bytes, MNT_NOWAIT)
    guard used > 0 else { return [] }
    var result: [MountPoint] = []
    for index in 0..<Int(used) {
        let fs = buffer[index]
        result.append(
            MountPoint(
                device: fixedString(fs.f_mntfromname),
                mountPoint: fixedString(fs.f_mntonname),
                fsType: fixedString(fs.f_fstypename)
            )
        )
    }
    return result
}

final class NtfsRemounter {
    private let ntfs3gPath = "/opt/homebrew/opt/ntfs-3g-t/bin/ntfs-3g"
    private let diskutilPath = "/usr/sbin/diskutil"
    private let ntfs3gLogPath = "/var/log/ntfsremount-ntfs3g.log"
    private let mountRoot = "/Volumes/"
    private let pollInterval: TimeInterval = 1.5
    private let retryCooldown: TimeInterval = 10.0

    private var cooldown: [String: Date] = [:]

    func run() {
        guard FileManager.default.isExecutableFile(atPath: ntfs3gPath) else {
            log("FATAL: ntfs-3g not found at \(ntfs3gPath)")
            return
        }
        FileManager.default.createFile(atPath: ntfs3gLogPath, contents: nil)
        log("started (ntfs-3g: \(ntfs3gPath), poll: \(pollInterval)s)")
        while true {
            tick()
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    private func tick() {
        let mounts = listMounts()
        let present = Set(mounts.map { $0.device })

        for mount in mounts where mount.fsType == "ntfs" && mount.mountPoint.hasPrefix(mountRoot) {
            if let last = cooldown[mount.device], Date().timeIntervalSince(last) < retryCooldown {
                continue
            }
            cooldown[mount.device] = Date()
            remount(mount)
        }

        for device in Array(cooldown.keys) where !present.contains(device) {
            cooldown.removeValue(forKey: device)
        }
    }

    private func remount(_ mount: MountPoint) {
        let label = (mount.mountPoint as NSString).lastPathComponent
        let (uid, gid) = consoleOwner()
        log("read-only NTFS \(mount.device) at \(mount.mountPoint); remounting read-write")

        let unmount = run(diskutilPath, ["unmount", "force", mount.device])
        if unmount.status != 0 {
            log("warning: unmount returned \(unmount.status): \(unmount.output.trimmed)")
        }

        var released = false
        for _ in 0..<10 {
            if fsType(at: mount.mountPoint) == nil {
                released = true
                break
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        if !released {
            log("warning: \(mount.mountPoint) still busy after unmount; leaving read-only")
            return
        }

        _ = run("/bin/mkdir", ["-p", mount.mountPoint])

        let options = [
            "local",
            "allow_other",
            "volname=\(label)",
            "uid=\(uid)",
            "gid=\(gid)",
            "umask=022",
        ].joined(separator: ",")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ntfs3gPath)
        process.arguments = ["-o", options, mount.device, mount.mountPoint]
        if let handle = FileHandle(forWritingAtPath: ntfs3gLogPath) {
            handle.seekToEndOfFile()
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        do {
            try process.run()
        } catch {
            log("error: could not launch ntfs-3g: \(error.localizedDescription)")
            restoreReadOnly(mount.device)
            return
        }

        // FUSE-T's ntfs-3g forks and the parent exits, so success must be
        // detected via the mount table rather than the process state.
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.5)
            if let type = fsType(at: mount.mountPoint), type != "ntfs" {
                log("mounted read-write: \(mount.device) -> \(mount.mountPoint)")
                return
            }
        }

        log("error: read-write mount failed; falling back to read-only")
        if process.isRunning { process.terminate() }
        restoreReadOnly(mount.device)
    }

    private func restoreReadOnly(_ device: String) {
        let result = run(diskutilPath, ["mount", device])
        if result.status != 0 {
            log("warning: could not restore read-only mount for \(device)")
        }
    }

    private func fsType(at path: String) -> String? {
        listMounts().first { $0.mountPoint == path }?.fsType
    }

    private func consoleOwner() -> (uid: String, gid: String) {
        let uid = run("/usr/bin/stat", ["-f", "%u", "/dev/console"]).output.trimmed
        let resolvedUID = uid.isEmpty ? "0" : uid
        let gid = run("/usr/bin/id", ["-g", resolvedUID]).output.trimmed
        return (resolvedUID, gid.isEmpty ? "0" : gid)
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

NtfsRemounter().run()
