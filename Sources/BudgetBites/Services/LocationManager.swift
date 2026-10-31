import Foundation
import CoreLocation

public final class LocationManager: NSObject, CLLocationManagerDelegate {
    public static let shared = LocationManager()
    
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    private var locationContinuation: CheckedContinuation<String, Error>?
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    public enum LocationError: LocalizedError {
        case authorizationDenied
        case locationUnavailable
        case geocodingFailed
        
        public var errorDescription: String? {
            switch self {
            case .authorizationDenied:
                return "Location access was denied. Please allow location access in Settings or enter your ZIP code manually."
            case .locationUnavailable:
                return "Could not determine current location. Please enter your ZIP code."
            case .geocodingFailed:
                return "Could not resolve ZIP code for your location. Please enter it manually."
            }
        }
    }
    
    /// Requests user location and reverse-geocodes to a 5-digit US ZIP code
    public func getCurrentZipCode() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            
            let status = manager.authorizationStatus
            switch status {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .restricted, .denied:
                continuation.resume(throwing: LocationError.authorizationDenied)
                self.locationContinuation = nil
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            @unknown default:
                continuation.resume(throwing: LocationError.locationUnavailable)
                self.locationContinuation = nil
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            if let cont = locationContinuation {
                cont.resume(throwing: LocationError.authorizationDenied)
                locationContinuation = nil
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            locationContinuation?.resume(throwing: LocationError.locationUnavailable)
            locationContinuation = nil
            return
        }
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            if let zip = placemarks?.first?.postalCode, !zip.isEmpty {
                self.locationContinuation?.resume(returning: zip)
            } else {
                self.locationContinuation?.resume(throwing: LocationError.geocodingFailed)
            }
            self.locationContinuation = nil
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}
