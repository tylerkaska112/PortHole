import SwiftUI
import Observation

struct Game: Codable, Identifiable, Equatable { var id = UUID(); var name: String; var exe: String; var args: String = "" }
final class AppModel: ObservableObject { @Published var games: [Game] = [Game(name: "Factorio", exe: #"C:\Factorio_2.0.77\bin\x64\factorio.exe"#), Game(name: "Celeste", exe: #"C:\Games\Celeste\Celeste.exe"#)]; func remove(_ g: Game) {} }
final class SessionController: ObservableObject {
    enum State: Equatable { case idle, enablingJIT, starting, running, ended, failed(String) }
    static let preciseMathKey = "p", audioCushionKey = "a"
    @Published var state: State = .idle; @Published var jitEnabled = false; var game: Game? = nil; var isActive: Bool { false }
    func refreshJIT() {}; func enableJIT() {}; func start(_ g: Game) {}; func dismiss() {}
}
enum PowerMode: Int, CaseIterable { case performance, balanced, saver
    var title: String { ["Performance", "Balanced", "Battery saver"][rawValue] }; var detail: String { ["60 FPS", "30 FPS", "30 FPS + Eco"][rawValue] } }
final class PowerManager { static let shared = PowerManager(); static let didChange = Notification.Name("x"); var userMode = PowerMode.balanced; func cycle() {}; func set(_ m: PowerMode) {} }
final class TunnelManager { static let shared = TunnelManager(); var isConnected = false; var statusText = "off"; var message: String? = nil; func disconnect() {}; func connect() async throws {} }
enum BuiltinJIT { static var hasPairing = true; static func importPairing(from: URL) throws {} }
struct Release { var title = "0.8.3" }
@Observable final class UpdateService { var available: Release? = Release(); var version = "0.8.2"; var build = "23" }
struct FilePickerSheet: View { var onPick: ([URL]) -> Void; var onCancel: () -> Void; var body: some View { Text("") } }
struct LogView: View { var body: some View { Text("log") } }
struct UpdatesView: View { var body: some View { Text("updates") } }

@main struct PreviewApp: App {
    @StateObject var model = AppModel(); @StateObject var session = SessionController(); @State var updates = UpdateService()
    var body: some Scene { WindowGroup {
        TabView {
            LibraryView(openSettings: {}, openUpdates: {}, openAdd: {}).environmentObject(model).environmentObject(session).environment(updates).tabItem { Text("Library") }
            SettingsView().environmentObject(session).environment(updates).tabItem { Text("Settings") }
        }.preferredColorScheme(.dark)
    } }
}
