import Foundation
import UIKit
import SafariServices
import AuthenticationServices

/// Errors specific to the Kroger integration layer.
public enum KrogerError: LocalizedError {
    case backendNotConfigured

    public var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "Kroger backend not configured. Add your KROGER_BACKEND_URL to Info.plist to enable live prices."
        }
    }
}

public struct KrogerStore: Codable, Identifiable, Equatable {
    public var id: String { locationId }
    public let locationId: String
    public let name: String
    public let addressLine1: String
    public let city: String
    public let state: String
    public let zipCode: String
    public let distance: Double?
    
    public var fullAddress: String {
        return "\(addressLine1), \(city), \(state) \(zipCode)"
    }
}

public struct KrogerCartItem: Codable, Equatable {
    public let upc: String
    public let quantity: Int
    
    public init(upc: String, quantity: Int) {
        self.upc = upc
        self.quantity = quantity
    }
}

public final class KrogerService {
    public static let shared = KrogerService()
    
    // Configurable backend URL (defaults to production backend or local)
    public var backendBaseURL: String = ""
    public var clientId: String = "budgetbites-client-id"
    public var redirectUri: String = ""
    
    private let urlSession = URLSession.shared
    
    // In-memory / on-device cache for store prices: (locationId -> [ConvertedPackagePrice], timestamp)
    private var localPriceCache: [String: (timestamp: Date, prices: [String: ConvertedPackagePrice])] = [:]
    private let cacheDuration: TimeInterval = 24 * 60 * 60 // 24 hours

    // Internal so WebViewContainer can check before triggering auto-fetch
    var hasBackend: Bool {
        guard !backendBaseURL.isEmpty else { return false }
        return !backendBaseURL.contains("example.com")
    }
    
    private init() {
        // Load default backend URL from Info.plist if configured
        if let customBackend = Bundle.main.object(forInfoDictionaryKey: "KROGER_BACKEND_URL") as? String,
           !customBackend.isEmpty {
            self.backendBaseURL = customBackend
        }
        if let customClientId = Bundle.main.object(forInfoDictionaryKey: "KROGER_CLIENT_ID") as? String,
           !customClientId.isEmpty {
            self.clientId = customClientId
        }
        if let customRedirect = Bundle.main.object(forInfoDictionaryKey: "KROGER_REDIRECT_URI") as? String,
           !customRedirect.isEmpty {
            self.redirectUri = customRedirect
        }
    }
    
    // MARK: - Selected Store Persistence
    public func getSelectedStore() -> KrogerStore? {
        guard let data = KeychainManager.shared.getData(forKey: .chosenStore) else { return nil }
        return try? JSONDecoder().decode(KrogerStore.self, from: data)
    }
    
    public func saveSelectedStore(_ store: KrogerStore) {
        if let data = try? JSONEncoder().encode(store) {
            KeychainManager.shared.save(data, forKey: .chosenStore)
        }
    }
    
    // MARK: - 1. Store Search
    public func fetchNearbyStores(zipCode: String? = nil, lat: Double? = nil, lon: Double? = nil) async throws -> [KrogerStore] {
        guard hasBackend else {
            throw KrogerError.backendNotConfigured
        }
        var components = URLComponents(string: "\(backendBaseURL)/api/kroger/locations")!
        var queryItems: [URLQueryItem] = []
        
        if let zip = zipCode, !zip.isEmpty {
            queryItems.append(URLQueryItem(name: "zipCode", value: zip))
        } else if let lat = lat, let lon = lon {
            queryItems.append(URLQueryItem(name: "lat", value: String(lat)))
            queryItems.append(URLQueryItem(name: "lon", value: String(lon)))
        } else {
            // Default: try CoreLocation
            let detectedZip = try await LocationManager.shared.getCurrentZipCode()
            queryItems.append(URLQueryItem(name: "zipCode", value: detectedZip))
        }
        
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        struct StoreResponse: Codable {
            struct RawStore: Codable {
                let locationId: String
                let name: String?
                let address: RawAddress?
                let distance: Double?
            }
            struct RawAddress: Codable {
                let addressLine1: String?
                let city: String?
                let state: String?
                let zipCode: String?
            }
            let stores: [RawStore]
        }
        
        let decoded = try JSONDecoder().decode(StoreResponse.self, from: data)
        return decoded.stores.map { s in
            KrogerStore(
                locationId: s.locationId,
                name: s.name ?? "Kroger",
                addressLine1: s.address?.addressLine1 ?? "",
                city: s.address?.city ?? "",
                state: s.address?.state ?? "",
                zipCode: s.address?.zipCode ?? "",
                distance: s.distance
            )
        }
    }
    
    // MARK: - 2. Live Price Fetching & Conversion
    public func fetchLivePrices(locationId: String) async throws -> [String: ConvertedPackagePrice] {
        guard hasBackend else {
            throw KrogerError.backendNotConfigured
        }
        // Check 24-hour in-memory/device cache
        if let cached = localPriceCache[locationId],
           Date().timeIntervalSince(cached.timestamp) < cacheDuration {
            return cached.prices
        }
        
        guard let url = URL(string: "\(backendBaseURL)/api/kroger/prices?locationId=\(locationId)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        struct BackendPriceItem: Codable {
            let upc: String?
            let name: String?
            let size: String?
            let regularPrice: Double?
            let promoPrice: Double?
            let price: Double?
            let isPromo: Bool?
            let inStock: Bool?
        }
        
        struct BackendPriceResponse: Codable {
            let locationId: String
            let updatedAt: String?
            let prices: [String: BackendPriceItem]
        }
        
        let decoded = try JSONDecoder().decode(BackendPriceResponse.self, from: data)
        var convertedDict: [String: ConvertedPackagePrice] = [:]
        
        for (key, item) in decoded.prices {
            guard let packagePrice = item.price ?? item.regularPrice, packagePrice > 0 else { continue }
            let converted = SizeToServingsConverter.convert(
                ingredientKey: key,
                upc: item.upc ?? "",
                productName: item.name ?? key,
                rawSize: item.size ?? "",
                packagePrice: packagePrice,
                isPromo: item.isPromo ?? false,
                inStock: item.inStock ?? true
            )
            convertedDict[key] = converted
        }
        
        // Cache result
        localPriceCache[locationId] = (timestamp: Date(), prices: convertedDict)
        return convertedDict
    }
    
    // MARK: - 3. Ensure Valid User Token (With Auto-Refresh)
    public func ensureValidToken(presentationAnchor: ASPresentationAnchor) async throws -> String {
        // Check if existing token is valid
        if let token = KeychainManager.shared.getString(forKey: .accessToken),
           let expString = KeychainManager.shared.getString(forKey: .tokenExpiration),
           let expTime = Double(expString),
           Date().timeIntervalSince1970 < (expTime - 60) {
            return token
        }
        
        // Try refresh token if available
        if let refreshToken = KeychainManager.shared.getString(forKey: .refreshToken), !refreshToken.isEmpty {
            do {
                return try await refreshTokenViaBackend(refreshToken)
            } catch {
                print("Token refresh failed, will prompt sign-in:", error)
            }
        }
        
        // Fall back to sign-in via ASWebAuthenticationSession
        return try await KrogerAuthManager.shared.authenticate(
            backendBaseURL: backendBaseURL,
            clientId: clientId,
            redirectUri: redirectUri,
            anchor: presentationAnchor
        )
    }
    
    public func refreshTokenViaBackend(_ refreshToken: String) async throws -> String {
        guard hasBackend else { throw KrogerError.backendNotConfigured }
        guard let url = URL(string: "\(backendBaseURL)/api/kroger/oauth/refresh") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        
        let expiresIn = json["expires_in"] as? Double ?? 1800
        let expirationDate = Date().addingTimeInterval(expiresIn)
        
        KeychainManager.shared.saveString(newAccessToken, forKey: .accessToken)
        if let newRefresh = json["refresh_token"] as? String, !newRefresh.isEmpty {
            KeychainManager.shared.saveString(newRefresh, forKey: .refreshToken)
        }
        KeychainManager.shared.saveString(String(expirationDate.timeIntervalSince1970), forKey: .tokenExpiration)
        
        return newAccessToken
    }
    
    // MARK: - 4. Add Items to Kroger Cart
    public func addToCart(items: [KrogerCartItem], presentationAnchor: ASPresentationAnchor) async throws -> Bool {
        guard hasBackend else { throw KrogerError.backendNotConfigured }
        guard !items.isEmpty else { return true }
        
        let token = try await ensureValidToken(presentationAnchor: presentationAnchor)
        
        guard let url = URL(string: "\(backendBaseURL)/api/kroger/cart") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let payload: [String: Any] = [
            "items": items.map { ["upc": $0.upc, "quantity": $0.quantity] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Cart API failure"
            throw NSError(domain: "KrogerService", code: 400, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        return true
    }
    
    // MARK: - 5. Open Kroger Cart Handoff
    public func openKrogerCart(from viewController: UIViewController) {
        let webCartURL = URL(string: "https://www.kroger.com/cart")!
        let appCartURL = URL(string: "kroger://cart")!
        
        // Try opening native Kroger app if installed
        if UIApplication.shared.canOpenURL(appCartURL) {
            UIApplication.shared.open(appCartURL, options: [:], completionHandler: nil)
            return
        }
        
        // Otherwise present SFSafariViewController
        let safariVC = SFSafariViewController(url: webCartURL)
        safariVC.modalPresentationStyle = .pageSheet
        safariVC.dismissButtonStyle = .close
        viewController.present(safariVC, animated: true, completion: nil)
    }
}
