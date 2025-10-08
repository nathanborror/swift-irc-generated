import IRC
import SwiftUI

struct ChannelView: View {
    @Environment(AppState.self) var state

    let channel: AppState.Channel

    @State var text = ""

    var messages: [Message] {
        state.events
            .compactMap {
                guard case .message(let message) = $0 else { return nil }
                return message
            }
            .filter {
                $0.params.first == channel.name
            }
    }

    var body: some View {
        @Bindable var state = state
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(messages.indices, id: \.self) { index in
                    switch messages[index].command {
                    case "JOIN":
                        HStack(spacing: 12) {
                            Text(timestamp(for: messages[index]))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            Text(Image(systemName: "door.left.hand.open"))
                                .fontWeight(.semibold)
                                .frame(width: 100, alignment: .trailing)
                            Text("\(messages[index].nick ?? "") joined")
                        }
                        .foregroundStyle(.secondary)
                    default:
                        HStack(spacing: 12) {
                            Text(timestamp(for: messages[index]))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            Text("\(messages[index].nick ?? "Unknown"):")
                                .fontWeight(.semibold)
                                .frame(width: 100, alignment: .trailing)
                            Text(messages[index].params.last ?? "")
                            Spacer()
                            Text(messages[index].command)
                        }
                    }
                }

            }
            .font(.system(size: 11, design: .monospaced))
            .padding()
        }
        .navigationTitle(channel.name)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                TextField("Message", text: $text)
                    .textFieldStyle(.plain)
                    .padding()
                    .onSubmit { handleSubmit() }
            }
        }
    }

    func handleSubmit() {
        guard !text.isEmpty else { return }

        // Check if this is a slash command
        if let command = SlashCommand.parse(text) {
            // Handle commands that need current channel context
            let finalCommand: SlashCommand
            switch command {
            case .topic(_, let newTopic):
                // If no channel specified, use current channel
                finalCommand = .topic(channel: channel.name, newTopic: newTopic)
            case .names(_):
                // Use current channel for names if not specified
                finalCommand = .names(channel: channel.name)
            default:
                finalCommand = command
            }

            state.executeSlashCommand(finalCommand, currentChannel: channel.name)
        } else {
            // Regular message
            state.privmsg(target: channel.name, text: text)
        }

        text = ""
    }

    func timestamp(for message: Message) -> String {
        if let timeTag = message.tags["time"] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: timeTag) {
                return Self.timeFormatter.string(from: date)
            }
        }

        // Fall back to current time if no server-time tag
        return Self.timeFormatter.string(from: Date())
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
