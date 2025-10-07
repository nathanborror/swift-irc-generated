import IRC
import SwiftUI

struct ChannelView: View {
    @Environment(AppState.self) var state

    let target: String

    @State var text = ""

    var messages: [Message] {
        state.events
            .compactMap {
                guard case .message(let message) = $0 else { return nil }
                return message
            }
            .filter {
                $0.params.first == target
            }
    }

    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(messages.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Text(messages[index].prefix ?? "Unknown")
                                .fontWeight(.semibold)
                                .frame(width: 200, alignment: .trailing)
                            Text(messages[index].params.last ?? "")
                        }
                        .font(.system(size: 11, design: .monospaced))
                    }
                }
                .padding()
            }
            TextField("Message", text: $text)
                .onSubmit {
                    handleSubmit()
                }
        }
    }

    func handleSubmit() {
        state.privmsg(target: target, text: text)
        text = ""
    }
}
