import Darwin
import Foundation

/// Read-only process names; does not collect command arguments, environment or conversation content.
public enum HarnessCLIActivity {
    public static func appIDs(processNames: Set<String>) -> Set<String> {
        Set(HarnessCatalog.supported.compactMap { definition in
            guard let cli = definition.commandLine else { return nil }
            let names = Set(cli.executableNames.flatMap { [$0, $0 + ".exe"] })
            return names.isDisjoint(with: processNames) ? nil : definition.appID
        })
    }

    public static func runningAppIDs() -> Set<String>? {
        var pids = [pid_t](repeating: 0, count: 32_768)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0, count < pids.count else { return nil }
        var names = Set<String>()
        for pid in pids.prefix(Int(count)) where pid > 0 {
            if Task.isCancelled { return nil }
            var buffer = [CChar](repeating: 0, count: 1024)
            let length = Int(proc_name(pid, &buffer, UInt32(buffer.count)))
            if length > 0 {
                names.insert(String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
        }
        return appIDs(processNames: names)
    }
}
