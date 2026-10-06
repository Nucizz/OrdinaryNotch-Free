import ServiceManagement

struct LoginItemClient {
    var status: () -> SMAppService.Status = { SMAppService.mainApp.status }
    var register: () throws -> Void = { try SMAppService.mainApp.register() }
    var openSettings: () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    var unregister: () throws -> Void = { try SMAppService.mainApp.unregister() }
}
