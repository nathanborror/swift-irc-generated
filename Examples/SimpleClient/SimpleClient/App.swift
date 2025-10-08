import SwiftUI
import IRC

@main
struct MainApp: App {
    @State var state = AppState.shared
    
    @State var joinChannel = "#general"

    var joined: [AppState.Channel] {
        Array(state.joined.values).sorted { $0.name < $1.name }
    }

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(selection: $state.selected) {
                    NavigationLink(value: AppState.Selection.console) {
                        Text("Console")
                    }
                    ForEach(joined, id: \.self) { channel in
                        NavigationLink(value: AppState.Selection.channel(channel)) {
                            Text(channel.name)
                        }
                    }
                }
                .navigationSplitViewColumnWidth(ideal: 200)
            } detail: {
                Group {
                    switch state.selected {
                    case .channel(let channel):
                        ChannelView(channel: channel)
                    case .console:
                        ConsoleView()
                    }
                }
                .toolbar {
                    ToolbarItem {
                        Button("Add Server", systemImage: "cloud") {
                            print("not implemented")
                        }
                    }
                    ToolbarSpacer(.fixed)
                    ToolbarItemGroup {
                        Button("Join", systemImage: "door.left.hand.open") {
                            handleShowJoin()
                        }
                        Button("Topic", systemImage: "flag") {
                            print("not implemented")
                        }
                        Button("Invite", systemImage: "person.crop.circle.badge.plus") {
                            print("not implemented")
                        }
                    }
                    ToolbarSpacer(.fixed)
                    ToolbarItem {
                        Button("Info", systemImage: "sidebar.right") {
                            state.showingInfo.toggle()
                        }
                    }
                }
            }
            .inspector(isPresented: $state.showingInfo) {
                ScrollView {
                    if case .channel(let channel) = state.selected {
                        VStack(alignment: .leading) {
                            ForEach(Array(channel.members), id: \.self) { member in
                                Text(member)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                        }
                    }
                }
                .inspectorColumnWidth(ideal: 200)
            }
            .sheet(isPresented: $state.showingJoinForm) {
                Form {
                    Section("Create New") {
                        TextField("Name", text: $joinChannel)
                            .frame(minWidth: 200)
                            .onSubmit { handleJoin() }
                    }
                    Section("Existing") {
                        ForEach(Array(state.channels.values), id: \.channel) { channel in
                            Button {
                                joinChannel = channel.channel
                                handleJoin()
                            } label: {
                                HStack {
                                    Text(channel.channel)
                                    Spacer()
                                    Text("\(channel.userCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Channels")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            state.showingJoinForm = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Join") {
                            handleJoin()
                        }
                    }
                }
            }
        }
        .environment(state)
        .defaultSize(width: 1400, height: 900)
    }

    func handleShowJoin() {
        state.showingJoinForm = true
        state.list()
    }

    func handleJoin() {
        guard !joinChannel.isEmpty else { return }
        state.join(joinChannel)
        state.showingJoinForm = false
        joinChannel = ""
    }
}
