import Foundation

/// Names shared by the app and its privileged helper.
public enum FanHelper {
    public static let machService = "dev.yan.islandmenu.helper"
    public static let daemonPlist = "dev.yan.islandmenu.helper.plist"
    public static let appIdentifier = "dev.yan.islandmenu"
    /// Developer team allowed to talk to the helper. Change this when building under another team.
    public static let teamIdentifier = "8GSUX2RHW8"
    /// The helper hands the fans back to macOS if it hears nothing for this long.
    public static let watchdogInterval: TimeInterval = 15
    public static let version = 1

    /// Only this app, signed by this team, may connect.
    public static var clientRequirement: String {
        "identifier \"\(appIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

/// What the root helper does on the app's behalf. It only ever touches the fan keys.
@objc public protocol FanHelperProtocol {
    func version(reply: @escaping (Int) -> Void)
    /// Forces each fan to the given speed in RPM (clamped to the fan's own range). Must be repeated
    /// within `FanHelper.watchdogInterval` or the helper reverts to automatic.
    func setFanSpeeds(_ rpm: [Double], reply: @escaping (Bool) -> Void)
    /// Returns fan control to macOS.
    func releaseFans(reply: @escaping (Bool) -> Void)
}
