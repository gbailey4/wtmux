import Foundation

public final class PTYProcess: @unchecked Sendable {
    public var onOutput: ((Data) -> Void)?

    private var masterFd: Int32 = -1
    private var childPid: pid_t = 0
    private var readSource: DispatchSourceRead?
    private var stopped = false

    public init() {}

    deinit {
        stop()
    }

    public func start(
        executable: String,
        environment: [String],
        currentDirectory: String,
        cols: UInt16,
        rows: UInt16
    ) {
        var winSize = winsize(
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        var masterFd: Int32 = -1
        let pid = forkpty(&masterFd, nil, nil, &winSize)

        if pid < 0 {
            return
        }

        if pid == 0 {
            // Child process
            if !currentDirectory.isEmpty {
                chdir(currentDirectory)
            }

            // Set environment variables
            for envVar in environment {
                let parts = envVar.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    setenv(String(parts[0]), String(parts[1]), 1)
                }
            }

            let shellName = "-" + (executable as NSString).lastPathComponent
            let argv: [UnsafeMutablePointer<CChar>?] = [
                strdup(shellName),
                nil
            ]
            execvp(executable, argv)
            _exit(1)
        }

        // Parent process
        self.masterFd = masterFd
        self.childPid = pid

        let source = DispatchSource.makeReadSource(fileDescriptor: masterFd, queue: .global(qos: .userInteractive))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = read(self.masterFd, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                self.onOutput?(data)
            } else if bytesRead <= 0 {
                self.stop()
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.masterFd >= 0 {
                close(self.masterFd)
                self.masterFd = -1
            }
        }
        source.resume()
        self.readSource = source
    }

    public func write(_ data: Data) {
        guard masterFd >= 0 else { return }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            _ = Foundation.write(masterFd, ptr, buffer.count)
        }
    }

    public func resize(cols: UInt16, rows: UInt16) {
        guard masterFd >= 0 else { return }
        var winSize = winsize(
            ws_row: rows,
            ws_col: cols,
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(masterFd, TIOCSWINSZ, &winSize)
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true

        readSource?.cancel()
        readSource = nil

        if childPid > 0 {
            kill(childPid, SIGHUP)
            var status: Int32 = 0
            waitpid(childPid, &status, WNOHANG)
            childPid = 0
        }
    }
}

