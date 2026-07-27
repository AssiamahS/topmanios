import SwiftUI
import WebKit

struct ContentView: View {
    @AppStorage("serverURL") private var serverURL = "saints-macbook-air.tail40af16.ts.net"
    @State private var showSettings = false
    @State private var reloadToken = 0
    @State private var phase: LoadPhase = .loading

    private var ink: Color { Color(red: 0.086, green: 0.082, blue: 0.102) }

    var body: some View {
        ZStack {
            ink.ignoresSafeArea()
            if let url = normalizedURL {
                WorkspaceWebView(url: url, reloadToken: reloadToken, phase: $phase)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay { statusOverlay }
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

    @ViewBuilder private var statusOverlay: some View {
        switch phase {
        case .loading:
            VStack(spacing: 14) {
                ProgressView()
                Text("Reaching your Mac…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Can't reach the Mac")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { reloadToken += 1 }
                    .buttonStyle(.borderedProminent)
            }
            .padding(32)
        case .loaded:
            EmptyView()
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
    @StateObject private var discovery = MacDiscovery()

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
            statusLine
        }
        .padding(28)
        .onAppear {
            discovery.onFound = { address in
                // never clobber an address the user typed themselves
                if serverURL.trimmingCharacters(in: .whitespaces).isEmpty {
                    serverURL = address
                }
            }
            if serverURL.trimmingCharacters(in: .whitespaces).isEmpty {
                discovery.start()
            }
        }
        .onDisappear { discovery.stop() }
    }

    @ViewBuilder private var statusLine: some View {
        switch discovery.status {
        case .searching:
            HStack(spacing: 8) {
                ProgressView()
                Text("Looking for your Mac…")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        case .found(let address):
            Label("Found \(address)", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .idle, .failed:
            EmptyView()
        }
    }
}

enum LoadPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}

struct WorkspaceWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: Int
    @Binding var phase: LoadPhase

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.086, green: 0.082, blue: 0.102, alpha: 1)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(url, in: webView)
        context.coordinator.lastReloadToken = reloadToken
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastURL != url || context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.load(url, in: webView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(phase: $phase) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastURL: URL?
        var lastReloadToken = 0
        private let phase: Binding<LoadPhase>
        private var retries = 0

        init(phase: Binding<LoadPhase>) {
            self.phase = phase
        }

        func load(_ url: URL, in webView: WKWebView) {
            lastURL = url
            retries = 0
            phase.wrappedValue = .loading
            webView.load(URLRequest(url: url, timeoutInterval: 8))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            retries = 0
            phase.wrappedValue = .loaded
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleFailure(error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleFailure(error, webView: webView)
        }

        // the tailscale tunnel can take a beat to wake from background — keep
        // retrying instead of leaving a silent black screen
        private func handleFailure(_ error: Error, webView: WKWebView) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            guard let url = lastURL else { return }
            if retries < 5 {
                retries += 1
                phase.wrappedValue = .loading
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak webView] in
                    webView?.load(URLRequest(url: url, timeoutInterval: 8))
                }
            } else {
                phase.wrappedValue = .failed(error.localizedDescription)
            }
        }
    }
}
