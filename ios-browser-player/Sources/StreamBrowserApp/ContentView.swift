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
        ZStack {
            AppBackground()

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
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(Color.black.opacity(0.45), for: .tabBar)
        }
        .tint(.indigo)
        .preferredColorScheme(.dark)
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
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    AddressBar(text: $addressText, onSubmit: {
                        openInput(addressText)
                    })
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                    if let currentWebURL {
                        BrowserView(url: currentWebURL)
                            .id(currentWebURL.absoluteString)
                            .background(Color.black)
                    } else {
                        WelcomeView(onExampleSelected: { value in
                            addressText = value
                            openInput(value)
                        })
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        BrandMark(size: 28)
                        Text(AppConfiguration.current.appName)
                            .font(.headline)
                    }
                }
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
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    AddressBar(text: $addressText, onSubmit: {
                        openInput(addressText)
                    })
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                    if let currentStreamURL {
                        VStack(spacing: 0) {
                            HLSPlayerView(url: currentStreamURL)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .frame(minHeight: 260)
                                .background(Color.black)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Flux HLS actif", systemImage: "dot.radiowaves.left.and.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.mint)
                                    Spacer()
                                    ShareLink(item: currentStreamURL) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    .accessibilityLabel("Partager le lien")
                                }

                                Text(currentStreamURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.ultraThinMaterial)
                    }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                    } else {
                        EmptyStateView(
                            title: "Aucun flux ouvert",
                            systemName: "play.rectangle",
                            description: "Collez un lien .m3u8 dans la barre ci-dessus pour lancer le lecteur."
                        )
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        BrandMark(size: 28)
                        Text("Lecteur vidéo")
                            .font(.headline)
                    }
                }
            }
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
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct WelcomeView: View {
    let onExampleSelected: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 38)

                BrandMark(size: 104)

                VStack(spacing: 10) {
                    Text("Le web, en grand.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("Recherchez, ouvrez vos liens et regardez vos flux HLS dans une seule app.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 28)
                }

                HStack(spacing: 10) {
                    WelcomePill(title: "Rechercher", systemName: "magnifyingglass")
                    WelcomePill(title: "Naviguer", systemName: "safari")
                    WelcomePill(title: "Regarder", systemName: "play.rectangle")
                }

                Button {
                    onExampleSelected("https://example.com")
                } label: {
                    Label("Ouvrir une première page", systemImage: "arrow.up.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollIndicators(.hidden)
    }
}

private struct WelcomePill: View {
    let title: String
    let systemName: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .scrollContentBackground(.hidden)
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

private struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.09)
                .ignoresSafeArea()

            Circle()
                .fill(Color.indigo.opacity(0.26))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .offset(x: 150, y: -270)

            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -160, y: 300)
        }
        .allowsHitTesting(false)
    }
}

private struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.indigo, Color.purple, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.42), lineWidth: max(1, size * 0.035))
                .padding(size * 0.18)

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.025)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.indigo.opacity(0.45), radius: size * 0.18, y: size * 0.08)
        .accessibilityHidden(true)
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