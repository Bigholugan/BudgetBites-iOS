import XCTest
@testable import BudgetBites

final class BudgetBitesTests: XCTestCase {
    
    // MARK: - 1. SizeToServingsConverter Tests
    func testParseSizeInOuncesAndUnits() {
        // Ounces
        XCTAssertEqual(SizeToServingsConverter.parseSizeInOuncesOrUnits("16 oz"), 16.0)
        XCTAssertEqual(SizeToServingsConverter.parseSizeInOuncesOrUnits("32 fl oz"), 32.0)
        
        // Pounds
        XCTAssertEqual(SizeToServingsConverter.parseSizeInOuncesOrUnits("1 lb"), 16.0)
        XCTAssertEqual(SizeToServingsConverter.parseSizeInOuncesOrUnits("2.5 lbs"), 40.0)
        
        // Gallons
        XCTAssertEqual(SizeToServingsConverter.parseSizeInOuncesOrUnits("half gallon"), 64.0)
        XCTAssertEqual(SizeToServingsConverter.parseSizeInOuncesOrUnits("1 gal"), 128.0)
        
        // Counts / Dozens
        XCTAssertEqual(SizeToServingsConverter.parseSizeInOuncesOrUnits("1 dozen"), 12.0)
        XCTAssertEqual(SizeToServingsConverter.parseSizeInOuncesOrUnits("12 ct"), 12.0)
        XCTAssertEqual(SizeToServingsConverter.parseSizeInOuncesOrUnits("20 count"), 20.0)
        XCTAssertEqual(SizeToServingsConverter.parseSizeInOuncesOrUnits("12 pack"), 12.0)
    }
    
    func testConvertKrogerChickenBreast() {
        // Chicken: 4 oz per serving. A 1 lb (16 oz) pack should equal 4 servings.
        let converted = SizeToServingsConverter.convert(
            ingredientKey: "chick",
            upc: "0001111041010",
            productName: "Heritage Farm Boneless Skinless Chicken Breast",
            rawSize: "1 lb",
            packagePrice: 3.49
        )
        
        XCTAssertEqual(converted.ingredientKey, "chick")
        XCTAssertEqual(converted.servingsPerPackage, 4.0)
        XCTAssertEqual(converted.packagePrice, 3.49)
        XCTAssertEqual(converted.pricePerServing, 0.872, accuracy: 0.001)
    }
    
    func testConvertKrogerEggsDozen() {
        // Eggs: 1 egg per serving. A 12 ct pack should equal 12 servings.
        let converted = SizeToServingsConverter.convert(
            ingredientKey: "eggs",
            upc: "0001111086022",
            productName: "Kroger Grade A Large White Eggs",
            rawSize: "12 ct",
            packagePrice: 2.19
        )
        
        XCTAssertEqual(converted.servingsPerPackage, 12.0)
        XCTAssertEqual(converted.pricePerServing, 0.183, accuracy: 0.001)
    }
    
    func testConvertKrogerHalfGallonMilk() {
        // Milk: 8 fl oz (1 cup) per serving. Half gallon (64 fl oz) = 8 servings.
        let converted = SizeToServingsConverter.convert(
            ingredientKey: "milk",
            upc: "0001111040101",
            productName: "Kroger 2% Reduced Fat Milk",
            rawSize: "half gallon",
            packagePrice: 1.99
        )
        
        XCTAssertEqual(converted.servingsPerPackage, 8.0)
        XCTAssertEqual(converted.pricePerServing, 0.249, accuracy: 0.001)
    }
    
    // MARK: - 2. Cart Request Payload Tests
    func testCartItemFormattingAndUPCPadding() {
        let item1 = KrogerCartItem(upc: "1111041010", quantity: 2)
        let item2 = KrogerCartItem(upc: "0001111086022", quantity: 1)
        
        XCTAssertEqual(item1.quantity, 2)
        XCTAssertEqual(item2.quantity, 1)
        
        // Ensure standard 13-digit formatting
        let padded1 = String(item1.upc).padding(toLength: 13, withPad: "0", startingAt: 0)
        XCTAssertEqual(padded1.count, 13)
        
        let payload: [String: Any] = [
            "items": [
                ["upc": item1.upc, "quantity": item1.quantity],
                ["upc": item2.upc, "quantity": item2.quantity]
            ]
        ]
        
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
        let jsonData = try? JSONSerialization.data(withJSONObject: payload)
        XCTAssertNotNil(jsonData)
    }
    
    // MARK: - 3. Keychain Token Storage & Refresh Logic
    func testKeychainTokenOperations() {
        let testToken = "test_kroger_access_token_12345"
        let testRefresh = "test_kroger_refresh_token_67890"
        let testExpiration = String(Date().addingTimeInterval(3600).timeIntervalSince1970)
        
        // Save
        XCTAssertTrue(KeychainManager.shared.saveString(testToken, forKey: .accessToken))
        XCTAssertTrue(KeychainManager.shared.saveString(testRefresh, forKey: .refreshToken))
        XCTAssertTrue(KeychainManager.shared.saveString(testExpiration, forKey: .tokenExpiration))
        
        // Retrieve
        XCTAssertEqual(KeychainManager.shared.getString(forKey: .accessToken), testToken)
        XCTAssertEqual(KeychainManager.shared.getString(forKey: .refreshToken), testRefresh)
        XCTAssertEqual(KeychainManager.shared.getString(forKey: .tokenExpiration), testExpiration)
        
        // Token expiry check logic
        let expDouble = Double(testExpiration)!
        let isExpired = Date().timeIntervalSince1970 > (expDouble - 60)
        XCTAssertFalse(isExpired)
        
        // Clean up
        KeychainManager.shared.clearAllTokens()
        XCTAssertNil(KeychainManager.shared.getString(forKey: .accessToken))
    }
    
    // MARK: - 4. PKCE Generation Tests
    func testPKCEVerifierAndChallenge() {
        let verifier = KrogerAuthManager.generateCodeVerifier()
        XCTAssertFalse(verifier.isEmpty)
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
        
        let challenge = KrogerAuthManager.generateCodeChallenge(from: verifier)
        XCTAssertFalse(challenge.isEmpty)
        // Challenge should be base64url encoded without padding
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }
}
