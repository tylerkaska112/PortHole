import Foundation

// Stand-ins for the app's own types, with only what the code under test uses.
struct LogEntry { enum Level { case info, error, success } }
final class LogStore { static let shared = LogStore(); var lines: [String] = []; func log(_ message: String, level: LogEntry.Level = .info) { lines.append(message) } }

struct Game: Codable, Equatable {
    var exe: String
    var args: String = ""
    var engine: GameEngine?
    var bindSets: [BindSet]?
    var activeBindSetID: UUID?
    var settings: GameSettings?
    var launchDirect: Bool?
    var dockAppID: Int?
    var settingsUndo: RecommendedSettings.Undo?
}
struct GameSettings: Codable, Equatable {
    var powerMode: Int?; var keepModeWhenHot: Bool?; var swapMB: Int?; var swapCoverage: String?; var vramMB: Int?; var audioCushionMs: Int?
    var preciseMath: Bool?; var dockDesktop: Bool?; var lookSensitivity: Double?; var resolution: String?
    var isEmpty: Bool { self == GameSettings() }
}
enum AppModel {
    nonisolated static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    nonisolated static var driveC: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("wine/drive_c") }
}
func wineserver_is_ready() -> Int32 { 1 }
func wineserver_is_running() -> Int32 { 1 }
