import Foundation

/// Resolves the user's preferred shell for terminal sessions.
public enum Shell {
    /// The shell path to use for new terminal sessions.
    ///
    /// Resolution order:
    /// 1. Explicit user setting (`UserDefaults` key `"defaultShell"`)
    /// 2. The user's login shell from Directory Services (`getpwuid`)
    /// 3. Fallback to `/bin/zsh`
    ///
    /// This deliberately ignores `ProcessInfo.processInfo.environment["SHELL"]`
    /// because the app may have been launched from a foreign context (e.g. a
    /// Claude Code zsh session) whose `SHELL` value doesn't reflect the user's
    /// actual preference.
    public static var `default`: String {
        // 1. Explicit user override from Settings
        if let stored = UserDefaults.standard.string(forKey: "defaultShell"),
           !stored.isEmpty {
            return stored
        }
        // 2. Login shell from Directory Services
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        // 3. Fallback
        return "/bin/zsh"
    }
}
