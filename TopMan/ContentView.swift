import SwiftUI
import WebKit

struct ContentView: View {
    @AppStorage("serverURL") private var serverURL = ""
    @State private var showSettings = false
    @State private var reloadToken = 0

    private var ink: Color { Color(red: 0.086, green: 0.082, blue: 0.102) }

    var body: some View {
        ZStack {
            ink.ignoresSafeArea()
            if let url = normalizedURL {
                WorkspaceWebView(url: url, reloadToken: reloadToken)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(.trailing, 14)
                    }
            } else {
                SetupView(serverURL: $serverURL)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SetupView(serverURL: $serverURL)
                    .navigationTitle("Server")
                    .toolbar {
                        Button("Done") {
                            showSettings = false
                            reloadToken += 1
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private var normalizedURL: URL? {
        let raw = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let withScheme = raw.contains("://") ? raw : "http://" + raw
        guard var comps = URLComponents(string: withScheme) else { return nil }
        if comps.port == nil { comps.port = 4477 }
        return comps.url
    }
}

struct SetupView: View {
    @Binding var serverURL: String

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(red: 0.36, green: 0.56, blue: 0.96))
            Text("TopMan")
                .font(.system(.largeTitle, design: .serif))
            Text("Point me at the Mac running your workspace — a Tailscale hostname or local IP.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("my-mac.tailnet-name.ts.net", text: $serverURL)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        }
        .padding(28)
    }
}

struct WorkspaceWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.086, green: 0.082, blue: 0.102, alpha: 1)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.load(URLRequest(url: url))
        context.coordinator.lastURL = url
        context.coordinator.lastReloadToken = reloadToken
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastURL != url || context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastURL = url
            context.coordinator.lastReloadToken = reloadToken
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastURL: URL?
        var lastReloadToken = 0
    }
}
