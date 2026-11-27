import Foundation
import IslandShared

/// Root daemon that writes the fan keys for Island Menu. It accepts connections only from the app
/// (checked by code signature) and gives the fans back to macOS when the app goes quiet or it exits.
final class FanService: NSObject, NSXPCListenerDelegate, FanHelperProtocol {
    private let queue = DispatchQueue(label: "dev.yan.islandmenu.helper.smc")
    private let smc = SMC()
    private var forced = false
    private var lastCommand = Date.distantPast
    private var watchdog: DispatchSourceTimer?

    private var fanCount: Int { Int(smc?.value("FNum") ?? 0) }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(FanHelper.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func version(reply: @escaping (Int) -> Void) {
        reply(FanHelper.version)
    }

    func setFanSpeeds(_ rpm: [Double], reply: @escaping (Bool) -> Void) {
        queue.async {
            reply(self.force(rpm))
        }
    }

    func releaseFans(reply: @escaping (Bool) -> Void) {
        queue.async {
            reply(self.release())
        }
    }

    private func force(_ rpm: [Double]) -> Bool {
        // The values come over XPC; anything that is not a plain number is refused outright.
        guard let smc, fanCount > 0, !rpm.isEmpty, rpm.allSatisfy(\.isFinite) else { return false }
        var succeeded = true
        for index in 0..<fanCount {
            guard let minimum = smc.value("F\(index)Mn"), let maximum = smc.value("F\(index)Mx"), maximum > minimum else {
                succeeded = false
                continue
            }
            let requested = index < rpm.count ? rpm[index] : (rpm.last ?? minimum)
            let target = Float32(min(max(requested, minimum), maximum))
            succeeded = smc.write("F\(index)md", byte: 1) && smc.write("F\(index)Tg", float: target) && succeeded
        }
        forced = true
        lastCommand = Date()
        startWatchdog()
        // A partial failure must not leave one fan forced with nothing renewing it.
        if !succeeded { _ = release() }
        return succeeded
    }

    @discardableResult
    private func release() -> Bool {
        guard let smc else { return false }
        var succeeded = true
        for index in 0..<fanCount where smc.value("F\(index)md") != 0 {
            succeeded = smc.write("F\(index)md", byte: 0) && succeeded
        }
        forced = false
        watchdog?.cancel()
        watchdog = nil
        return succeeded
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, self.forced, Date().timeIntervalSince(self.lastCommand) > FanHelper.watchdogInterval else { return }
            self.release()
        }
        timer.resume()
        watchdog = timer
    }

    /// Releases synchronously; used on the way out.
    func shutdown() {
        queue.sync { _ = release() }
    }
}

let service = FanService()
let listener = NSXPCListener(machServiceName: FanHelper.machService)
listener.delegate = service
listener.resume()

// launchd stops the daemon with SIGTERM; leave the fans automatic before going.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    service.shutdown()
    exit(0)
}
termination.resume()
dispatchMain()
