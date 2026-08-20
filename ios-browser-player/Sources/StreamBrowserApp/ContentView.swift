import SwiftUI

private enum AppTab: Hashable {
    case browser
    case player
    case offline
}

struct ContentView: View {
    @EnvironmentObject private var browserStore: BrowserStore
    @EnvironmentObject private var offlineStore: OfflineStore
    @State private var addressText = ""
    @State private var currentWebURL: URL?
    @State private var currentStreamURL: URL?
    @State private var selectedTab: AppTab = .browser
    @State private var showingHistory = false
    @State private var showingDownloadOptions = false
    @State private var pendingDownloadURL: URL?
    @State private var availableQualities: [VideoQuality] = []
    @State private var isResolvingQualities = false
    @State private var downloadError: String?
    @State private var selectedOfflineVideo: OfflineVideo?

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

                offlineTab
                    .tabItem {
                        Label("Hors ligne", systemImage: "arrow.down.circle")
                    }
                    .tag(AppTab.offline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(Color.black.opacity(0.45), for: .tabBar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .sheet(isPresented: $showingDownloadOptions, onDismiss: clearDownloadSelection) {
            DownloadOptionsView(
                url: pendingDownloadURL,
                qualities: availableQualities,
                isLoading: isResolvingQualities,
                errorMessage: downloadError,
                onSelect: { quality in
                    offlineStore.startDownload(quality, title: title(for: quality.url))
                    showingDownloadOptions = false
                    selectedTab = .offline
                }
            )
        }
        .sheet(item: $selectedOfflineVideo) { video in
            OfflinePlayerSheet(video: video, localURL: offlineStore.localURL(for: video))
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
                        BrowserView(
                            url: currentWebURL,
                            onLinkLongPress: beginDownload(for:),
                            onVideoURL: openVideoURL(_:)
                        )
                            .id(currentWebURL.absoluteString)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                    } else {
                        WelcomeView(onExampleSelected: { value in
                            addressText = value
                            openInput(value)
                        })
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                     Button {
                                         beginDownload(for: currentStreamURL)
                                     } label: {
                                         Label("Télécharger", systemImage: "arrow.down.circle.fill")
                                             .font(.caption.weight(.semibold))
                                     }
                                     .buttonStyle(.borderedProminent)
                                     .controlSize(.small)
                                     .tint(.indigo)
                                     .accessibilityLabel("Télécharger cette vidéo")
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var offlineTab: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if offlineStore.videos.isEmpty {
                    EmptyStateView(
                        title: "Aucune vidéo hors ligne",
                        systemName: "arrow.down.circle",
                        description: "Faites un appui long sur un lien vidéo dans le navigateur pour choisir une qualité et la télécharger."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(offlineStore.videos) { video in
                                OfflineVideoRow(
                                    video: video,
                                    progress: offlineStore.progress[video.id] ?? 0,
                                    onOpen: {
                                        guard offlineStore.localURL(for: video) != nil else { return }
                                        selectedOfflineVideo = video
                                    },
                                    onDelete: {
                                        offlineStore.remove(video)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Hors ligne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        BrandMark(size: 28)
                        Text("Hors ligne")
                            .font(.headline)
                    }
                }
            }
        }
    }

    private func openInput(_ input: String) {
        guard let url = browserStore.resolveInput(input) else { return }
        browserStore.addToHistory(url)

        if browserStore.isVideo(url) {
            openVideoURL(url)
        } else {
            currentWebURL = url
            selectedTab = .browser
        }
    }

    private func openVideoURL(_ url: URL) {
        currentStreamURL = url
        browserStore.addToHistory(url)
        selectedTab = .player
    }

    private func beginDownload(for url: URL) {
        pendingDownloadURL = url
        availableQualities = []
        downloadError = nil
        showingDownloadOptions = true

        isResolvingQualities = true
        Task {
            do {
                let qualities = try await VideoQualityResolver.resolve(for: url)
                guard pendingDownloadURL == url else { return }
                availableQualities = qualities
            } catch {
                guard pendingDownloadURL == url else { return }
                downloadError = error.localizedDescription
            }
            isResolvingQualities = false
        }
    }

    private func clearDownloadSelection() {
        pendingDownloadURL = nil
        availableQualities = []
        isResolvingQualities = false
        downloadError = nil
    }

    private func title(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Vidéo téléchargée" : name.replacingOccurrences(of: "-", with: " ")
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

private struct DownloadOptionsView: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL?
    let qualities: [VideoQuality]
    let isLoading: Bool
    let errorMessage: String?
    let onSelect: (VideoQuality) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Télécharger la vidéo", systemImage: "arrow.down.circle.fill")
                                .font(.title2.weight(.bold))

                            if let url {
                                Text(url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                        }

                        if isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Recherche des qualités disponibles…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else if let errorMessage {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.orange)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                        } else {
                            Text("Choisissez une qualité")
                                .font(.headline)

                            ForEach(qualities) { quality in
                                Button {
                                    onSelect(quality)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "film")
                                            .font(.title3)
                                            .foregroundStyle(.indigo)
                                            .frame(width: 34, height: 34)
                                            .background(Color.indigo.opacity(0.16), in: Circle())

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(quality.label)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text(quality.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.indigo)
                                    }
                                    .padding(14)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Téléchargement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct OfflineVideoRow: View {
    let video: OfflineVideo
    let progress: Double
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.indigo.opacity(0.85), Color.purple.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: video.status == .completed ? "play.fill" : "arrow.down")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 5) {
                    Text(video.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(video.qualityLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.indigo)

                    switch video.status {
                    case .completed:
                        Label(
                            video.errorMessage ?? "Disponible hors ligne",
                            systemImage: "checkmark.circle.fill"
                        )
                            .font(.caption)
                            .foregroundStyle(.mint)
                    case .downloading:
                        ProgressView(value: progress)
                            .tint(.indigo)
                        Text(progress > 0 ? "\(Int(progress * 100)) %" : "Téléchargement en cours…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .converting:
                        ProgressView(value: progress)
                            .tint(.indigo)
                        Text("Conversion en MP4…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .failed:
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Échec du téléchargement", systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)

                            if let errorMessage = video.errorMessage,
                               !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                if video.status == .completed || video.status == .converting {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(video.status != .completed)
        .contextMenu {
            Button("Supprimer", role: .destructive, action: onDelete)
        }
    }
}

private struct OfflinePlayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let video: OfflineVideo
    let localURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let localURL {
                    HLSPlayerView(url: localURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyStateView(
                        title: "Vidéo indisponible",
                        systemName: "exclamationmark.triangle",
                        description: "Le fichier local n’est plus disponible."
                    )
                }
            }
            .navigationTitle(video.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let localURL {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: localURL) {
                            Label("Exporter", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
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