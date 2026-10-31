import SwiftUI
import WebKit
import SafariServices
import AuthenticationServices

struct WebViewContainer: UIViewRepresentable {
    @Environment(\.colorScheme) var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Register native message handlers
        contentController.add(context.coordinator, name: "haptic")
        contentController.add(context.coordinator, name: "kroger")
        configuration.userContentController = contentController

        // Allow local file access for bundled html, css, js
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.scrollView.bounces = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false

        // Match background to current color scheme to eliminate white flash
        webView.backgroundColor = colorScheme == .dark
            ? UIColor(red: 17/255, green: 22/255, blue: 17/255, alpha: 1.0)
            : UIColor(red: 246/255, green: 247/255, blue: 242/255, alpha: 1.0)

        // Locate bundled index.html across SwiftPM (xtool) and Xcode bundles
        var targetURL: URL?

        #if SWIFT_PACKAGE
        targetURL = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "www") ??
                    Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Resources/www") ??
                    Bundle.module.url(forResource: "index", withExtension: "html")
        #endif

        if targetURL == nil {
            targetURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") ??
                        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Resources/www") ??
                        Bundle.main.url(forResource: "index", withExtension: "html")
        }

        if let indexURL = targetURL {
            let directoryURL = indexURL.deletingLastPathComponent()
            webView.loadFileURL(indexURL, allowingReadAccessTo: directoryURL)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Update the webview background when the system color scheme changes
        uiView.backgroundColor = colorScheme == .dark
            ? UIColor(red: 17/255, green: 22/255, blue: 17/255, alpha: 1.0)
            : UIColor(red: 246/255, green: 247/255, blue: 242/255, alpha: 1.0)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebViewContainer
        weak var webView: WKWebView?

        init(_ parent: WebViewContainer) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "haptic" {
                handleHaptic(message.body)
            } else if message.name == "kroger" {
                handleKroger(message.body)
            }
        }

        private func handleHaptic(_ body: Any) {
            let type = (body as? String) ?? "light"
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
                case "success":
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)
                case "warning":
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.warning)
                case "error":
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.error)
                default:
                    let feedback = UIImpactFeedbackGenerator(style: .light)
                    feedback.impactOccurred()
                }
            }
        }

        private func handleKroger(_ body: Any) {
            guard let dict = body as? [String: Any],
                  let action = dict["action"] as? String else { return }

            Task { @MainActor in
                switch action {
                case "init":
                    // Send currently saved store if any
                    if let saved = KrogerService.shared.getSelectedStore() {
                        let json = (try? JSONEncoder().encode(saved)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
                        self.evaluateJS("window.onKrogerStoreLoaded && window.onKrogerStoreLoaded(\(json));")
                        
                        // Only auto-fetch prices if a real backend is configured
                        if KrogerService.shared.hasBackend {
                            self.loadPricesForStore(locationId: saved.locationId)
                        }
                    }

                    // Send current Kroger account link status
                    let isLinked = KrogerService.shared.isAccountLinked
                    self.evaluateJS("window.onKrogerAccountStatus && window.onKrogerAccountStatus({ linked: \(isLinked) });")

                case "linkAccount":
                    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let anchor = windowScene.windows.first(where: { $0.isKeyWindow }) else {
                        self.evaluateJS("window.onKrogerAccountStatus && window.onKrogerAccountStatus({ linked: false, error: 'Unable to present sign-in window' });")
                        return
                    }
                    do {
                        let _ = try await KrogerService.shared.linkAccount(presentationAnchor: anchor)
                        self.evaluateJS("window.onKrogerAccountStatus && window.onKrogerAccountStatus({ linked: true, message: 'Kroger account linked successfully!' });")
                    } catch {
                        let errMsg = error.localizedDescription.replacingOccurrences(of: "'", with: "\\'")
                        self.evaluateJS("window.onKrogerAccountStatus && window.onKrogerAccountStatus({ linked: false, error: '\(errMsg)' });")
                    }

                case "unlinkAccount":
                    KrogerService.shared.unlinkAccount()
                    self.evaluateJS("window.onKrogerAccountStatus && window.onKrogerAccountStatus({ linked: false, message: 'Kroger account unlinked' });")

                case "searchStores":
                    let zipCode = dict["zipCode"] as? String
                    let useGPS = dict["useGPS"] as? Bool ?? false
                    do {
                        var zipToSearch = zipCode
                        if useGPS {
                            zipToSearch = try await LocationManager.shared.getCurrentZipCode()
                        }
                        let stores = try await KrogerService.shared.fetchNearbyStores(zipCode: zipToSearch)
                        let encoded = try JSONEncoder().encode(stores)
                        let jsonStr = String(data: encoded, encoding: .utf8) ?? "[]"
                        self.evaluateJS("window.onKrogerStoresList && window.onKrogerStoresList(\(jsonStr));")
                    } catch {
                        let errMsg = error.localizedDescription.replacingOccurrences(of: "'", with: "\\'")
                        self.evaluateJS("window.onKrogerStoresError && window.onKrogerStoresError('\(errMsg)');")
                    }

                case "selectStore":
                    if let storeData = dict["store"] as? [String: Any],
                       let jsonData = try? JSONSerialization.data(withJSONObject: storeData),
                       let store = try? JSONDecoder().decode(KrogerStore.self, from: jsonData) {
                        KrogerService.shared.saveSelectedStore(store)
                        self.evaluateJS("window.onKrogerStoreSelected && window.onKrogerStoreSelected(\(String(data: jsonData, encoding: .utf8) ?? "null"));")
                        self.loadPricesForStore(locationId: store.locationId)
                    }

                case "fetchPrices":
                    if let locationId = dict["locationId"] as? String {
                        self.loadPricesForStore(locationId: locationId)
                    }

                case "sendCart":
                    guard let rawItems = dict["items"] as? [[String: Any]], !rawItems.isEmpty else {
                        self.sendCartStatus(success: false, count: 0, error: "No items provided to send to cart.")
                        return
                    }
                    let items = rawItems.compactMap { it -> KrogerCartItem? in
                        guard let upc = it["upc"] as? String, !upc.isEmpty else { return nil }
                        let qty = (it["quantity"] as? Int) ?? 1
                        return KrogerCartItem(upc: upc, quantity: qty)
                    }

                    guard !items.isEmpty else {
                        self.sendCartStatus(success: false, count: 0, error: "No items with valid UPC codes to send.")
                        return
                    }

                    guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let anchor = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first else {
                        self.sendCartStatus(success: false, count: 0, error: "Unable to present sign-in window.")
                        return
                    }

                    do {
                        let success = try await KrogerService.shared.addToCart(items: items, presentationAnchor: anchor)
                        self.sendCartStatus(success: success, count: items.count, error: nil)
                        self.evaluateJS("window.onKrogerAccountStatus && window.onKrogerAccountStatus({ linked: true });")
                    } catch {
                        self.sendCartStatus(success: false, count: 0, error: error.localizedDescription)
                    }

                case "openCart":
                    if let topVC = self.getTopViewController() {
                        KrogerService.shared.openKrogerCart(from: topVC)
                    }

                default:
                    break
                }
            }
        }

        @MainActor
        private func getTopViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) ??
                               scenes.first?.windows.first,
                  let root = window.rootViewController else {
                return nil
            }
            var top = root
            while let presented = top.presentedViewController, !presented.isBeingDismissed {
                top = presented
            }
            return top
        }

        @MainActor
        private func sendCartStatus(success: Bool, count: Int, error: String?) {
            var payload: [String: Any] = [
                "success": success,
                "count": count
            ]
            if let error = error {
                payload["error"] = error
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let jsonString = String(data: data, encoding: .utf8) {
                self.evaluateJS("window.onKrogerCartStatus && window.onKrogerCartStatus(\(jsonString));")
            }
        }

        private func loadPricesForStore(locationId: String) {
            Task { @MainActor in
                do {
                    let prices = try await KrogerService.shared.fetchLivePrices(locationId: locationId)
                    var priceDict: [String: Any] = [:]
                    for (k, v) in prices {
                        priceDict[k] = [
                            "upc": v.upc,
                            "name": v.productName,
                            "size": v.rawSize,
                            "packagePrice": v.packagePrice,
                            "servings": v.servingsPerPackage,
                            "pricePerServing": v.pricePerServing,
                            "isPromo": v.isPromo,
                            "inStock": v.inStock
                        ]
                    }
                    let payload: [String: Any] = [
                        "locationId": locationId,
                        "updatedAt": ISO8601DateFormatter().string(from: Date()),
                        "prices": priceDict
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: payload),
                       let json = String(data: data, encoding: .utf8) {
                        self.evaluateJS("window.onKrogerPricesLoaded && window.onKrogerPricesLoaded(\(json));")
                    }
                } catch {
                    let errMsg = error.localizedDescription.replacingOccurrences(of: "'", with: "\\'")
                    self.evaluateJS("window.onKrogerPricesError && window.onKrogerPricesError('\(errMsg)');")
                }
            }
        }

        private func evaluateJS(_ script: String) {
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(script, completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Signal webview that native bridge is ready
            evaluateJS("window.isNativeApp = true; window.dispatchEvent(new Event('NativeBridgeReady'));")
        }

        // Suppress system-level navigation error alerts — the page handles errors in-app
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsErr = error as NSError
            // Ignore cancelled loads (e.g. redirects) and web-content-process crashes
            if nsErr.code == NSURLErrorCancelled { return }
            print("[WebView] provisional navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsErr = error as NSError
            if nsErr.code == NSURLErrorCancelled { return }
            print("[WebView] navigation failed: \(error.localizedDescription)")
        }
    }
}
