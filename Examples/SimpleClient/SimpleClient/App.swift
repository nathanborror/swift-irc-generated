import SwiftUI

@main
struct MainApp: App {
    @State var state = AppState.shared
    @State var selectedTarget = ""

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(selection: $selectedTarget) {
                    Text("Console").tag("")

                    ForEach(state.channels, id: \.self) { channel in
                        Text(channel).tag(channel)
                    }
                }
            } detail: {
                if selectedTarget.isEmpty {
                    ConsoleView()
                } else {
                    ChannelView(target: selectedTarget)
                }
            }
        }
        .environment(state)
        .commands {
            CommandMenu("IRC") {
                Button("Connect") {
                    state.connect()
                }
            }
        }
    }
}
