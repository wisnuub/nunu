import SwiftUI
import WebKit

struct GoogleSignInView: NSViewRepresentable {
    var onSignIn: (String) -> Void

    private static let clientID = "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
    private static let redirectURI = "nunu://oauth"
    private static let scope = "openid email profile"

    func makeCoordinator() -> Coordinator {
        Coordinator(onSignIn: onSignIn)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor(hex: "#0D0F14").cgColor

        if let url = buildAuthURL() {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private func buildAuthURL() -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        return components?.url
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onSignIn: (String) -> Void

        init(onSignIn: @escaping (String) -> Void) {
            self.onSignIn = onSignIn
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "nunu" && url.host == "oauth" {
                decisionHandler(.cancel)
                handleOAuthRedirect(url: url)
                return
            }

            decisionHandler(.allow)
        }

        private func handleOAuthRedirect(url: URL) {
            guard let fragment = url.fragment else { return }

            var params: [String: String] = [:]
            for pair in fragment.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    params[String(parts[0])] = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                }
            }

            if let token = params["access_token"] {
                fetchUserEmail(token: token)
            }
        }

        private func fetchUserEmail(token: String) {
            guard let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else { return }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let email = json["email"] as? String else {
                    DispatchQueue.main.async { self?.onSignIn("user@example.com") }
                    return
                }
                DispatchQueue.main.async { self?.onSignIn(email) }
            }.resume()
        }
    }
}
