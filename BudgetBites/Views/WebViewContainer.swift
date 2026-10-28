import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Register haptic message handler
        contentController.add(context.coordinator, name: "haptic")
        configuration.userContentController = contentController

        // Allow local file access for bundled html, css, js
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 246/255, green: 247/255, blue: 242/255, alpha: 1.0)

        // Load local index.html bundled in app
        if let wwwURL = Bundle.main.url(forResource: "www", withExtension: nil),
           let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") {
            webView.loadFileURL(indexURL, allowingReadAccessTo: wwwURL)
        } else if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            let bundleURL = Bundle.main.bundleURL
            webView.loadFileURL(indexURL, allowingReadAccessTo: bundleURL)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebViewContainer

        init(_ parent: WebViewContainer) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "haptic" {
                let type = (message.body as? String) ?? "light"
                DispatchQueue.main.async {
                    switch type {
                    case "selection":
                        let feedback = UISelectionFeedbackGenerator()
                        feedback.selectionChanged()
                    case "medium":
                        let feedback = UIImpactFeedbackGenerator(style: .medium)
                        feedback.impactOccurred()
                    case "heavy":
                        let feedback = UIImpactFeedbackGenerator(style: .heavy)
                        feedback.impactOccurred()
                    default:
                        let feedback = UIImpactFeedbackGenerator(style: .light)
                        feedback.impactOccurred()
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Web view finished loading
        }
    }
}
