import Foundation

enum AppIdentity {
    static var storeName: String {
        Bundle.main.infoDictionary?["WTMuxStoreName"] as? String ?? "WTEasy"
    }

    static var notificationPrefix: String {
        Bundle.main.infoDictionary?["WTMuxNotificationPrefix"] as? String
            ?? "com.grahampark.wtmux"
    }

    static var mcpServerName: String {
        Bundle.main.infoDictionary?["WTMuxMCPServerName"] as? String
            ?? "wtmux"
    }

    static var importProjectNotification: NSNotification.Name {
        .init("\(notificationPrefix).importProject")
    }

    static var claudeStatusNotification: NSNotification.Name {
        .init("\(notificationPrefix).claudeStatus")
    }
}
