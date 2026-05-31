import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var manager = RDPManager()
    @StateObject private var recentStore = RecentConnectionStore()

    @AppStorage("lastHost") private var host = ""
    @AppStorage("lastUser") private var user = ""
    @AppStorage("lastPort") private var port = 3389
    @AppStorage("selectedResolution") private var selectedResolution = "1024 x 768"
    @AppStorage("selectedColorDepth") private var colorDepth = 32
    @AppStorage("enableRemoteFx") private var enableRemoteFx = true
    @AppStorage("enableAudioPlayback") private var enableAudioPlayback = true
    @AppStorage("rememberPassword") private var rememberPassword = false
    @AppStorage("sharedFolderPath") private var sharedFolderPath = ""

    @State private var password = ""
    @State private var passwordFocused = false

    private var resolution: ResolutionOption {
        ResolutionOption.all.first { $0.label == selectedResolution } ?? ResolutionOption.all[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            RemoteDesktopView(
                isConnected: manager.isConnected,
                image: manager.image,
                remoteSize: manager.remoteSize,
                onMouse: manager.sendMouse,
                onUnicode: manager.sendUnicode,
                onScancode: manager.sendScancode,
                onAppleKeycode: manager.sendAppleKeycode
            )
            .background(Color.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !manager.isConnected {
                connectionBar
            }
        }
        .onAppear {
            loadSavedPasswordIfAvailable()
            if !host.isEmpty, !user.isEmpty {
                passwordFocused = true
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(manager.status)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Text(HardwareCapabilities.current.shortLabel)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .help(HardwareCapabilities.current.detail)
            if manager.isConnected {
                Button("Disconnect") {
                    manager.disconnect()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var connectionBar: some View {
        HStack(spacing: 8) {
            Menu("Recent") {
                if recentStore.profiles.isEmpty {
                    Text("No recent connections")
                } else {
                    ForEach(recentStore.profiles) { profile in
                        Button("\(profile.host) - \(profile.user)") {
                            select(profile)
                        }
                    }
                    Divider()
                    ForEach(recentStore.profiles) { profile in
                        Button("Remove \(profile.host)") {
                            recentStore.remove(profile)
                        }
                    }
                }
            }
            .frame(width: 86)

            TextField("Host", text: $host, onCommit: connect)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)

            TextField("Port", text: Binding(
                get: { String(port) },
                set: { port = Int($0) ?? 3389 }
            ), onCommit: connect)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)

            TextField("User", text: $user, onCommit: connect)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)

            SecurePasswordField(
                text: $password,
                isFocused: $passwordFocused,
                placeholder: "Password",
                onCommit: connect
            )
            .frame(width: 180)

            Picker("Resolution", selection: $selectedResolution) {
                ForEach(ResolutionOption.all) { option in
                    Text(option.label).tag(option.label)
                }
            }
            .frame(width: 150)

            Picker("Color", selection: $colorDepth) {
                Text("16").tag(16)
                Text("24").tag(24)
                Text("32").tag(32)
            }
            .frame(width: 88)

            Toggle("RemoteFX", isOn: $enableRemoteFx)
            Toggle("Audio", isOn: $enableAudioPlayback)
            Toggle("Keychain", isOn: $rememberPassword)

            Button(sharedFolderTitle) {
                chooseSharedFolder()
            }
            if !sharedFolderPath.isEmpty {
                Button("Clear") {
                    sharedFolderPath = ""
                }
            }

            Button("Connect") {
                connect()
            }
            .disabled(manager.isConnecting)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var sharedFolderTitle: String {
        guard !sharedFolderPath.isEmpty else {
            return "Folder"
        }

        let name = URL(fileURLWithPath: sharedFolderPath).lastPathComponent
        return name.isEmpty ? "Folder" : name
    }

    private func select(_ profile: ConnectionProfile) {
        host = profile.host
        port = Int(profile.port)
        user = profile.user
        password = KeychainPasswordStore.password(host: profile.host, port: profile.port, user: profile.user) ?? ""
        rememberPassword = !password.isEmpty
        passwordFocused = true
    }

    private func loadSavedPasswordIfAvailable() {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty, !normalizedUser.isEmpty else {
            return
        }

        if let savedPassword = KeychainPasswordStore.password(
            host: normalizedHost,
            port: Int32(max(1, min(65535, port))),
            user: normalizedUser
        ) {
            password = savedPassword
            rememberPassword = true
        }
    }

    private func connect() {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPort = Int32(max(1, min(65535, port)))

        guard !normalizedHost.isEmpty else {
            manager.status = "Enter a host"
            return
        }

        guard !normalizedUser.isEmpty else {
            manager.status = "Enter a username"
            return
        }

        guard !password.isEmpty else {
            manager.status = "Enter a password"
            passwordFocused = true
            return
        }

        host = normalizedHost
        user = normalizedUser
        port = Int(normalizedPort)
        recentStore.touch(host: normalizedHost, port: normalizedPort, user: normalizedUser)

        if rememberPassword {
            KeychainPasswordStore.save(password, host: normalizedHost, port: normalizedPort, user: normalizedUser)
        } else {
            KeychainPasswordStore.delete(host: normalizedHost, port: normalizedPort, user: normalizedUser)
        }

        manager.connect(
            host: normalizedHost,
            port: normalizedPort,
            user: normalizedUser,
            pass: password,
            settings: RDPConnectionSettings(
                width: resolution.width,
                height: resolution.height,
                colorDepth: Int32(colorDepth),
                enableRemoteFx: enableRemoteFx,
                enableAudioPlayback: enableAudioPlayback,
                sharedFolderName: sharedFolderName,
                sharedFolderPath: sharedFolderPath.isEmpty ? nil : sharedFolderPath
            )
        )
    }

    private var sharedFolderName: String? {
        guard !sharedFolderPath.isEmpty else {
            return nil
        }

        let name = URL(fileURLWithPath: sharedFolderPath).lastPathComponent
        return name.isEmpty ? "Mac" : name
    }

    private func chooseSharedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if !sharedFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: sharedFolderPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            sharedFolderPath = url.path
        }
    }
}
