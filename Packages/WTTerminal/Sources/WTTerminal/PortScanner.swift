import Darwin

/// Detects TCP LISTEN ports for a process tree using macOS libproc APIs.
public enum PortScanner {

    /// Returns the set of TCP ports in LISTEN state for the given PID and all its descendants.
    public static func listeningPorts(forProcessTree pid: pid_t) -> Set<UInt16> {
        let pids = collectDescendants(of: pid)
        var ports = Set<UInt16>()
        for p in pids {
            ports.formUnion(listeningPorts(forPID: p))
        }
        return ports
    }

    // MARK: - Private

    /// Collects `pid` plus all descendant PIDs recursively.
    private static func collectDescendants(of pid: pid_t) -> [pid_t] {
        var result = [pid]
        var queue = [pid]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            var childPids = [pid_t](repeating: 0, count: 256)
            let bufferSize = Int32(MemoryLayout<pid_t>.size * childPids.count)
            let count = proc_listchildpids(current, &childPids, bufferSize)
            if count > 0 {
                let children = Array(childPids.prefix(Int(count)))
                result.append(contentsOf: children)
                queue.append(contentsOf: children)
            }
        }
        return result
    }

    /// Returns TCP LISTEN ports for a single PID.
    private static func listeningPorts(forPID pid: pid_t) -> Set<UInt16> {
        // Get the list of file descriptors
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let fdCount = Int(bufferSize) / MemoryLayout<proc_fdinfo>.size
        var fdInfos = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdInfos, bufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize) / MemoryLayout<proc_fdinfo>.size
        var ports = Set<UInt16>()

        for i in 0..<actualCount {
            let fd = fdInfos[i]
            // Only inspect socket file descriptors
            guard fd.proc_fdtype == PROX_FDTYPE_SOCKET else { continue }

            var socketInfo = socket_fdinfo()
            let socketInfoSize = Int32(MemoryLayout<socket_fdinfo>.size)
            let result = proc_pidfdinfo(
                pid,
                fd.proc_fd,
                PROC_PIDFDSOCKETINFO,
                &socketInfo,
                socketInfoSize
            )
            guard result == socketInfoSize else { continue }

            // Check for TCP socket in LISTEN state
            let si = socketInfo.psi
            guard si.soi_kind == SOCKINFO_TCP else { continue }

            let tcpInfo = si.soi_proto.pri_tcp
            guard tcpInfo.tcpsi_state == TSI_S_LISTEN else { continue }

            // Extract the local port (stored in network byte order)
            let rawPort = si.soi_proto.pri_tcp.tcpsi_ini.insi_lport
            let port = UInt16(bigEndian: UInt16(rawPort & 0xFFFF))
            if port > 0 {
                ports.insert(port)
            }
        }

        return ports
    }
}
