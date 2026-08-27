import Foundation
import ServiceManagement

/// Whether macOS starts Pulse when the user logs in.
///
/// The registration lives in the system's login-items database, not in Pulse's
/// preferences, and the user can turn it off in System Settings without Pulse
/// hearing about it. So this reads the system every time rather than keeping a
/// copy that would quietly go out of date.
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the login item can be registered at all. A binary run straight
    /// from the build directory has no app bundle to register, so the setting
    /// is not offered there rather than failing when it is used.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// - Returns: whether the change took, so the caller can show what the
    ///   system actually thinks rather than what was asked for.
    @discardableResult
    static func setEnabled(_ enabled: Bool) throws -> Bool {
        let service = SMAppService.mainApp
        if enabled {
            // Registering an already-registered service throws rather than
            // doing nothing, and "already on" is not an error worth showing.
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled {
            try service.unregister()
        }
        return isEnabled
    }

    /// What to tell the user when the system refuses. The common refusal is a
    /// login item the user disabled by hand, which only they can turn back on.
    static func explain(_ error: Error) -> String {
        if SMAppService.mainApp.status == .requiresApproval {
            return "macOS is holding this login item for approval. Turn ClaudePulse on under Login Items in System Settings."
        }
        return error.localizedDescription
    }
}
