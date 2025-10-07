import IRC
import SwiftUI

struct ConsoleView: View {
    @Environment(AppState.self) var state

    var messages: [Message] {
        state.events.compactMap {
            guard case .message(let message) = $0 else { return nil }
            return message
        }
    }

    var body: some View {
        switch state.state {
        case .connecting:
            ContentUnavailableView("Connecting...", systemImage: "icloud")
        case .connected:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(messages.indices, id: \.self) { index in
                        Text(messages[index].raw)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
                .padding()
                .toolbar {
                    ToolbarItem {
                        Button {
                            state.join("#general")
                        } label: {
                            Label("Join", systemImage: "door.left.hand.open")
                        }
                    }
                }
            }
        case .disconnected:
            VStack {
                ContentUnavailableView("Disconnected", systemImage: "icloud.slash")
                Button("Connect") {
                    state.connect()
                }
            }
        }
    }
}
