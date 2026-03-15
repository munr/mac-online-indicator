import ServiceManagement

class LoginItemManager {

    static let shared = LoginItemManager()

    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item.
    /// - Returns: The error if the operation failed, or `nil` on success.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Error? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error
        }
    }
}
