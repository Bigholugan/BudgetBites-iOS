import Foundation

public struct ConvertedPackagePrice: Equatable {
    public let ingredientKey: String
    public let upc: String
    public let productName: String
    public let rawSize: String
    public let packagePrice: Double
    public let servingsPerPackage: Double
    public let pricePerServing: Double
    public let isPromo: Bool
    public let inStock: Bool
    
    public init(
        ingredientKey: String,
        upc: String,
        productName: String,
        rawSize: String,
        packagePrice: Double,
        servingsPerPackage: Double,
        pricePerServing: Double,
        isPromo: Bool,
        inStock: Bool
    ) {
        self.ingredientKey = ingredientKey
        self.upc = upc
        self.productName = productName
        self.rawSize = rawSize
        self.packagePrice = packagePrice
        self.servingsPerPackage = servingsPerPackage
        self.pricePerServing = pricePerServing
        self.isPromo = isPromo
        self.inStock = inStock
    }
}

public final class SizeToServingsConverter {
    
    // Standard baseline serving weight or count in base units (oz, ct, count)
    private static let standardServingSizes: [String: Double] = [
        "eggs": 1.0,      // 1 egg
        "oats": 1.38,     // ~1.38 oz per 0.5 cup dry oats
        "banana": 1.0,    // 1 banana
        "milk": 8.0,      // 8 fl oz (1 cup)
        "yog": 6.0,       // 6 oz (~0.75 cup)
        "chick": 4.0,     // 4 oz
        "turk": 4.0,      // 4 oz
        "tuna": 5.0,      // 5 oz
        "bean": 4.5,      // ~4.5 oz (0.5 cup)
        "lent": 1.75,     // ~1.75 oz (0.25 cup dry)
        "rice": 1.75,     // ~1.75 oz (0.25 cup dry)
        "bread": 2.0,     // 2 slices (~2 oz)
        "sweet": 1.0,     // 1 potato
        "pasta": 2.0,     // 2 oz dry
        "broc": 4.0,      // ~4 oz frozen
        "spin": 5.0,      // ~5 oz frozen
        "mix": 4.0,       // ~4 oz frozen
        "carrot": 4.0,    // ~4 oz
        "tom": 4.5,       // ~4.5 oz
        "onion": 0.5,     // 0.5 onion
        "pb": 1.14,       // ~1.14 oz (2 tbsp)
        "oil": 0.5,       // 0.5 fl oz (1 tbsp)
        "apple": 1.0,     // 1 apple
        "ched": 1.0,      // 1 oz
        "tort": 1.0,      // 1 tortilla
        "whey": 1.05,     // ~1.05 oz (1 scoop)
        "cott": 4.0,      // 4 oz (0.5 cup)
        "berry": 4.0,     // ~4 oz (1 cup)
        "salmon": 4.0,    // 4 oz
        "avocado": 0.5,   // 0.5 avocado
        "almond": 1.0,    // 1 oz
        "quinoa": 1.5,    // ~1.5 oz (0.25 cup dry)
        "tea": 1.0,       // 1 bag
        "coffee": 0.4,    // ~0.4 oz per cup grounds
        "sparkling": 1.0, // 1 can
        "soda": 1.0,      // 1 can
        "wine": 5.0       // 5 fl oz (1 glass)
    ]
    
    // Default fallback servings if string cannot be parsed
    private static let fallbackServings: [String: Double] = [
        "eggs": 12.0, "oats": 13.0, "banana": 3.0, "milk": 8.0,
        "yog": 5.0, "chick": 4.0, "turk": 4.0, "tuna": 1.0,
        "bean": 3.0, "lent": 9.0, "rice": 9.0, "bread": 10.0,
        "sweet": 2.0, "pasta": 8.0, "broc": 3.0, "spin": 2.0,
        "mix": 3.0, "carrot": 4.0, "tom": 3.0, "onion": 2.0,
        "pb": 14.0, "oil": 16.0, "apple": 3.0, "ched": 8.0,
        "tort": 8.0, "whey": 30.0, "cott": 4.0, "berry": 3.0,
        "salmon": 4.0, "avocado": 4.0, "almond": 8.0, "quinoa": 8.0,
        "tea": 20.0, "coffee": 30.0, "sparkling": 12.0, "soda": 12.0,
        "wine": 5.0
    ]
    
    /// Parses numeric quantity and unit from strings like "16 oz", "1 lb", "12 ct", "1 gal", "750 ml"
    public static func parseSizeInOuncesOrUnits(_ rawString: String) -> Double? {
        let text = rawString.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        
        // 1. Gallons to fluid ounces (1 gal = 128 fl oz, 0.5 gal / half gal = 64 fl oz)
        if text.contains("half gallon") || text.contains("1/2 gal") {
            return 64.0
        }
        if text.contains("gal") {
            if let num = extractFirstNumber(text) {
                return num * 128.0
            }
            return 128.0
        }
        
        // 2. Pounds to ounces (1 lb = 16 oz)
        if text.contains("lb") || text.contains("pound") {
            if let num = extractFirstNumber(text) {
                return num * 16.0
            }
            return 16.0
        }
        
        // 3. Ounces / Fluid Ounces
        if text.contains("oz") || text.contains("fl oz") {
            if let num = extractFirstNumber(text) {
                return num
            }
        }
        
        // 4. Milliliters (750 ml ~ 25.4 fl oz)
        if text.contains("ml") {
            if let num = extractFirstNumber(text) {
                return num * 0.033814
            }
        }
        
        // 5. Count / Pack / Ct / Dozen
        if text.contains("dozen") {
            if let num = extractFirstNumber(text) {
                return num * 12.0
            }
            return 12.0
        }
        if text.contains("ct") || text.contains("count") || text.contains("pk") || text.contains("pack") {
            if let num = extractFirstNumber(text) {
                return num
            }
        }
        
        // 6. Plain number
        if let num = extractFirstNumber(text) {
            return num
        }
        
        return nil
    }
    
    private static func extractFirstNumber(_ s: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: s.utf16.count)
        if let match = regex.firstMatch(in: s, options: [], range: range),
           let r = Range(match.range(at: 1), in: s) {
            return Double(s[r])
        }
        return nil
    }
    
    /// Converts a Kroger product size & price into app servings and cost per serving
    public static func convert(
        ingredientKey: String,
        upc: String,
        productName: String,
        rawSize: String,
        packagePrice: Double,
        isPromo: Bool = false,
        inStock: Bool = true
    ) -> ConvertedPackagePrice {
        let fallback = fallbackServings[ingredientKey] ?? 1.0
        let singleServingSize = standardServingSizes[ingredientKey] ?? 1.0
        
        var servings: Double = fallback
        
        if let parsedTotalUnits = parseSizeInOuncesOrUnits(rawSize), parsedTotalUnits > 0 {
            let calculated = parsedTotalUnits / singleServingSize
            // Round to nearest integer if >= 1, otherwise retain precision
            servings = calculated >= 1.0 ? round(calculated) : round(calculated * 100) / 100
        }
        
        if servings <= 0 {
            servings = fallback
        }
        
        let pricePerServing = (packagePrice / servings)
        
        return ConvertedPackagePrice(
            ingredientKey: ingredientKey,
            upc: upc,
            productName: productName,
            rawSize: rawSize,
            packagePrice: packagePrice,
            servingsPerPackage: servings,
            pricePerServing: (round(pricePerServing * 1000) / 1000),
            isPromo: isPromo,
            inStock: inStock
        )
    }
}
