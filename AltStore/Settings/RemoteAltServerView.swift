//
//  RemoteAltServerView.swift
//  AltStore
//
//  Created by Caroline Moore on 5/26/26.
//  Copyright © 2026 Riley Testut. All rights reserved.
//

import SwiftUI

import AltStoreCore

struct RemoteAltServerView: View
{
    @State
    private var availableServers: [AnisetteServer]? = AnisetteServerManager.shared.cachedServers
    
    @State
    private var isLoading = true
    
    @State
    private var preferredURL: URL? = UserDefaults.shared.preferredAnisetteServerURL
    
    @State
    private var customURLText: String = ""
    
    @State
    private var isShowingError = false
    
    @State
    private var errorMessage = ""
    
    @State
    private var isConnected = false

    @State
    private var clientInfo: AnisetteClientInfo?

    @State
    private var clientInfoURL: URL?

    @State
    private var isLoadingClientInfo = false

    @State
    private var clientInfoError: String?

    @State
    private var clientInfoRequestID = UUID()

    @State
    private var isSelectingServer = false

    @State
    private var isShowingClearConfirmation = false
    
    @Environment(\.dismiss)
    private var dismiss

    private var localizedTitle: String { String(localized: "Remote AltServer") }

    var body: some View {
        List {
            Section {
                LabeledContent("Status") {
                    HStack {
                        Text(isConnected ? "Connected" : "Not Connected")
                        Image(systemName: "circle.fill")
                            .font(.caption)
                            .foregroundStyle(isConnected ? Color.green : Color.red)
                            .accessibilityHidden(true)
                    }
                }

                if isConnected, let preferredURL
                {
                    LabeledContent("Anisette Server", value: preferredURL.host ?? preferredURL.absoluteString)

                    if clientInfoURL == preferredURL, let clientInfo
                    {
                        LabeledContent("Device", value: clientInfo.deviceType ?? String(localized: "Unknown"))
                        LabeledContent("Platform", value: clientInfo.operatingSystem ?? String(localized: "Unknown"))
                    }
                    else if isLoadingClientInfo
                    {
                        ProgressView("Loading server details…")
                    }
                    else if let clientInfoError
                    {
                        Text(clientInfoError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(isConnected ? "The device connection is ready." : "Turn on Wi-Fi and LocalDevVPN to connect.")
            }
            .listSectionSpacing(10) // Visually differentiates sections of different types.
            
            if let availableServers
            {
                Section("Popular") {
                    ForEach(availableServers) { server in
                        SwiftUI.Button {
                            Task { await selectServer(url: server.url) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(server.name)
                                    
                                    Text(server.url.host ?? "")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if server.url == preferredURL
                                {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(.rect) // Expand tap target to the full row.
                        }
                        .buttonStyle(.plain)
                        .disabled(isSelectingServer)
                    }
                }
            }
            else if isLoading
            {
                Section("Popular") {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            Section("Custom") {
                HStack {
                    TextField("https://", text: $customURLText)
                        .disabled(isSelectingServer)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit {
                            Task { await submitCustom() }
                        }

                    if isCustomSelected
                    {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            
            Section {
                SwiftUI.Button(role: .destructive) {
                    isShowingClearConfirmation = true
                } label: {
                    Text("Reset Remote AltServer")
                        .frame(maxWidth: .infinity)
                }
                .confirmationDialog("Are you sure you want to reset Remote AltServer?", isPresented: $isShowingClearConfirmation, titleVisibility: .visible) {
                    SwiftUI.Button("Reset", role: .destructive) {
                        clearRemoteAltServer()
                    }
                } message: {
                    Text("You'll need to go through setup again to use it.")
                }
            }
        }
        .navigationTitle(localizedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadServers() }
        .refreshable {
            await loadServers()
            await loadClientInfo()
        }
        .task { await monitorConnection() }
        .task(id: isConnected ? preferredURL : nil) { await loadClientInfo() }
        .alert("Couldn't select server", isPresented: $isShowingError) {
            SwiftUI.Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
    }

    private var isCustomSelected: Bool
    {
        guard let preferredURL, let availableServers else { return false }
        return !availableServers.contains { $0.url == preferredURL }
    }
}

private extension RemoteAltServerView
{
    func loadServers() async
    {
        isLoading = true
        defer { isLoading = false }

        do
        {
            availableServers = try await AnisetteServerManager.shared.fetchServers()
        }
        catch
        {
            // Keep showing cached servers (if any).
            Logger.sideload.error("Failed to load anisette servers: \(error.localizedDescription, privacy: .public)")
        }

        // If preferred URL isn't in the list, it's the user's custom server.
        if let preferredURL, availableServers?.contains(where: { $0.url == preferredURL }) != true
        {
            customURLText = preferredURL.absoluteString.replacingOccurrences(of: "\(preferredURL.scheme ?? "")://", with: "") // Remove scheme for display
        }
    }

    // Pings the server, then makes it the preferred server. Leaves selection unchanged if it's unreachable.
    func selectServer(url: URL) async
    {
        guard url != preferredURL, !isSelectingServer else { return }
        isSelectingServer = true
        defer { isSelectingServer = false }

        do
        {
            try await AnisetteServerManager.shared.validate(url)
        }
        catch
        {
            errorMessage = error.localizedDescription
            isShowingError = true
            return
        }

        UserDefaults.shared.preferredAnisetteServerURL = url
        preferredURL = url

        // An adi.pb is provider-specific. Force the next request to provision
        // against the newly selected server.
        Keychain.shared.anisetteADIPB = nil
        Keychain.shared.anisetteADIPBServerURL = nil
        Keychain.shared.anisetteProvisioningClientInfo = nil
        Keychain.shared.anisetteProvisioningUserAgent = nil

        // Clear the custom field when selecting a known server.
        if availableServers?.contains(where: { $0.url == url }) == true
        {
            customURLText = ""
        }
    }

    func submitCustom() async
    {
        var input = customURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        
        if !input.hasPrefix("http://") && !input.hasPrefix("https://")
        {
            input = "https://\(input)"
        }
        
        guard let url = URL(string: input) else
        {
            errorMessage = String(localized: "The provided URL is invalid.")
            isShowingError = true
            return
        }

        await selectServer(url: url)
    }
    
    func monitorConnection() async
    {
        while true
        {
            isConnected = await OnDeviceClient.isReachable()

            // Automatic fallback can change the saved provider while this view
            // is visible. Update both the checkmark and the identity details.
            let storedURL = UserDefaults.shared.preferredAnisetteServerURL
            if preferredURL != storedURL
            {
                preferredURL = storedURL
                if let storedURL, availableServers?.contains(where: { $0.url == storedURL }) != true
                {
                    customURLText = storedURL.absoluteString
                }
                else
                {
                    customURLText = ""
                }
            }
            
            do
            {
                try await Task.sleep(for: .seconds(2)) // Often enough to feel live without spamming the check.
            }
            catch
            {
                break // View disappeared, so we can stop monitoring.
            }
        }
    }

    func loadClientInfo() async
    {
        let requestID = UUID()
        clientInfoRequestID = requestID
        clientInfo = nil
        clientInfoURL = nil
        clientInfoError = nil
        isLoadingClientInfo = false
        guard isConnected, let url = preferredURL else { return }

        isLoadingClientInfo = true
        defer {
            if clientInfoRequestID == requestID { isLoadingClientInfo = false }
        }
        do
        {
            let info = try await AnisetteServerManager.shared.validate(url)
            guard !Task.isCancelled, clientInfoRequestID == requestID, isConnected, preferredURL == url else { return }
            clientInfo = info
            clientInfoURL = url
        }
        catch
        {
            guard !Task.isCancelled, clientInfoRequestID == requestID, isConnected, preferredURL == url else { return }
            clientInfoError = error.localizedDescription
        }
    }
    
    func clearRemoteAltServer()
    {
        UserDefaults.shared.prefersRemoteAltServer = false
        UserDefaults.shared.ignoresBundledPairingFile = true
        Keychain.shared.devicePairingFile = nil
        
        UserDefaults.shared.preferredAnisetteServerURL = nil
        Keychain.shared.anisetteADIPB = nil
        Keychain.shared.anisetteADIPBServerURL = nil
        Keychain.shared.anisetteProvisioningClientInfo = nil
        Keychain.shared.anisetteProvisioningUserAgent = nil
        
        dismiss() // Return to Settings
    }
}

extension RemoteAltServerView
{
    static func makeViewController() -> UIHostingController<some View>
    {
        let view = RemoteAltServerView()

        let hostingController = UIHostingController(rootView: view)
        hostingController.navigationItem.largeTitleDisplayMode = .never
        hostingController.navigationItem.title = view.localizedTitle
        return hostingController
    }
}

#Preview {
    NavigationStack {
        RemoteAltServerView()
    }
}
