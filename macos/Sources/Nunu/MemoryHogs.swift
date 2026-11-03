import Darwin
import Foundation

/// Other Mac apps ranked by physical footprint (incl. compressed memory),
/// with helper processes summed into their app ("Google Chrome Helper" -> Chrome).
enum MemoryHogs {
    struct App {
        let name: String
        let mb: Int
    }

    static func top(limit: Int, atLeastMB: Int) -> [App] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var totals: [String: UInt64] = [:]
        let me = getpid()
        for pid in pids.prefix(Int(max(n, 0))) where pid > 0 && pid != me {
            var path = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let p = String(cString: path)
            // nunu's own engine is what we're trying to make room for.
            guard !p.hasPrefix(Paths.root.path), let app = appName(p) else { continue }
            var info = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) == 0
                }
            }
            if ok { totals[app, default: 0] += info.ri_phys_footprint }
        }
        return totals
            .map { App(name: $0.key, mb: Int($0.value >> 20)) }
            .filter { $0.mb >= atLeastMB && $0.name != "nunu" }
            .sorted { $0.mb > $1.mb }
            .prefix(limit)
            .map { $0 }
    }

    /// Outermost "X.app" in a path; nil for system daemons.
    private static func appName(_ path: String) -> String? {
        guard let r = path.range(of: ".app/") else { return nil }
        let head = path[..<r.lowerBound]
        guard let slash = head.lastIndex(of: "/") else { return nil }
        return String(head[head.index(after: slash)...])
    }
}
