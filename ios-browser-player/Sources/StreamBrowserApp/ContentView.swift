import SwiftUI

private enum AppTab: Hashable {
    case browser
    case player
}

struct ContentView: View {
    @EnvironmentObject private var browserStore: BrowserStore
    @State private var addressText = ""
    @State private var currentWebURL: URL?
    @State private var currentStreamURL: URL?
    @State private var selectedTab: AppTab = .browser
    @State private var showingHistory = false

    var body: some View {
        TabView(selection: $selectedTab) {
            browserTab
                .tabItem {
                    Label("Navigateur", systemImage: "safari")
                }
                .tag(AppTab.browser)

            playerTab
                .tabItem {
                    Label("Lecteur", systemImage: "play.rectangle")
                }
                .tag(AppTab.player)
        }
        .tint(.indigo)
        .sheet(isPresented: $showingHistory) {
            HistoryView { item in
                addressText = item.url
                showingHistory = false
                openInput(item.url)
            }
            .environmentObject(browserStore)
        }
    }

    private var browserTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AddressBar(text: $addressText, onSubmit: {
                    openInput(addressText)
                })
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 8)

                if let currentWebURL {
                    BrowserView(url: currentWebURL)
                        .id(currentWebURL.absoluteString)
                } else {
                    WelcomeView(onExampleSelected: { value in
                        addressText = value
                        openInput(value)
                    })
                }
            }
            .navigationTitle(AppConfiguration.current.appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Afficher l'historique")
                }
            }
        }
    }

    private var playerTab: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AddressBar(text: $addressText, onSubmit: {
                    openInput(addressText)
                })
                .padding(.horizontal)
                .padding(.top, 10)

                if let currentStreamURL {
                    HLSPlayerView(url: currentStreamURL)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Flux actuel")
                            .font(.headline)
                        Text(currentStreamURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    ShareLink(item: currentStreamURL) {
                        Label("Partager le lien", systemImage: "square.and.arrow.up")
                    }
                } else {
                    EmptyStateView(
                        title: "Aucun flux ouvert",
                        systemName: "play.rectangle",
                        description: "Collez un lien .m3u8 dans la barre ci-dessus pour lancer le lecteur."
                    )
                }

                Spacer()
            }
            .navigationTitle("Lecteur vidéo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func openInput(_ input: String) {
        guard let url = browserStore.resolveInput(input) else { return }
        browserStore.addToHistory(url)

        if browserStore.isHLS(url) {
            currentStreamURL = url
            selectedTab = .player
        } else {
            currentWebURL = url
            selectedTab = .browser
        }
    }
}

private struct AddressBar: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Rechercher ou coller un lien", text: $text)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Effacer")
            }

            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.indigo)
            }
            .accessibilityLabel("Ouvrir")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary, in: Capsule())
    }
}

private struct WelcomeView: View {
    let onExampleSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "safari.fill")
                .font(.system(size: 48))
                .foregroundStyle(.indigo)

            Text("Rechercher ou ouvrir un lien")
                .font(.title3.weight(.semibold))

            Text("Entrez une adresse web, une recherche ou un lien HLS direct se terminant par .m3u8.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)

            Button("Tester avec example.com") {
                onExampleSelected("https://example.com")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var browserStore: BrowserStore
    let onSelect: (HistoryItem) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if browserStore.history.isEmpty {
                    EmptyStateView(
                        title: "Historique vide",
                        systemName: "clock",
                        description: "Les liens ouverts apparaîtront ici."
                    )
                } else {
                    List(browserStore.history) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.url)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text(item.visitedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Historique")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Effacer", role: .destructive) {
                        browserStore.clearHistory()
                    }
                    .disabled(browserStore.history.isEmpty)
                }
            }
        }
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemName: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}