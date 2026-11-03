import SwiftUI

@main
struct EpaperBridgeApp: App {
    @StateObject private var receiver = BLEReceiver()
    @StateObject private var writer = NFCWriter()
    @StateObject private var templateStore = TemplateStore()
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    DashboardView(receiver: receiver, writer: writer)
                }
                .tabItem {
                    Label("主控台", systemImage: "macwindow.and.cursorarrow")
                }
                .tag(0)

                NavigationStack {
                    StudioView(receiver: receiver, templateStore: templateStore, selectedTab: $selectedTab)
                }
                .tabItem {
                    Label("創作與範本", systemImage: "sparkles.rectangle.stack")
                }
                .tag(1)

                NavigationStack {
                    DiagnosticsView(receiver: receiver, writer: writer, selectedTab: $selectedTab)
                }
                .tabItem {
                    Label("測試與診斷", systemImage: "wrench.and.screwdriver")
                }
                .tag(2)
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background { receiver.stop() }
            }
        }
    }
}
