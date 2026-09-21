import Foundation

// MARK: - SSHAgentPeer

/// Who is on the other end of a connection.
///
/// Both fields are optional in effect — `pid` is absent when the kernel will not say, `name` when
/// the executable cannot be resolved — because a prompt that cannot name the requester still has to
/// be answerable. `name == nil` is a real answer, not a failure to be papered over with a guess.
nonisolated struct SSHAgentPeer: Hashable, Sendable {
    let pid: Int32
    /// The executable's file name, e.g. `git` or `ssh`. Nil when `proc_pidpath` declined.
    let name: String?
}

// MARK: - SSHAgentPeerProcess

/// Asks the kernel which process opened a Unix socket connection.
///
/// This exists for one reason: a master-password prompt that does not say **what** is asking trains
/// the user to approve without reading, which is the same as having no prompt. `git` and a script
/// someone was tricked into running look identical on the wire; they do not look identical here.
///
/// Verified on this machine before it was relied on: `LOCAL_PEERPID` on a connected `AF_UNIX`
/// socket returns `0` and the peer's pid, `proc_pidpath` resolves it, and an unconnected socket
/// returns `-1` — which is why `pid > 0` is part of the guard rather than an afterthought.
nonisolated enum SSHAgentPeerProcess {

    /// The process that connected, or nil when the kernel will not identify it.
    ///
    /// - Parameter fd: A connected socket. A listening socket has no peer and yields nil.
    static func peer(forDescriptor fd: Int32) -> SSHAgentPeer? {
        var pid: pid_t = 0
        var length   = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0, pid > 0 else {
            return nil
        }
        return SSHAgentPeer(pid: Int32(pid), name: executableName(of: pid))
    }

    /// The last path component of the peer's executable.
    ///
    /// The name rather than the whole path: `/usr/bin/ssh` and `/opt/homebrew/bin/ssh` are the same
    /// thing to a user deciding whether to approve, and a long path pushes the key name out of the
    /// line the prompt has room for.
    private static func executableName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = (String(cString: buffer) as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
