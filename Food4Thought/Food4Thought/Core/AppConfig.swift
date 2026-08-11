import Foundation

/// Typed access to build configuration.
///
/// Backed by `Secrets.swift`, which is gitignored and generated from
/// `Config/Secrets.xcconfig.example`. Missing values surface as compile errors
/// rather than runtime failures, so a misconfigured checkout cannot ship.
enum AppConfig {

    static let supabaseURL: URL = {
        guard let url = URL(string: "https://\(Secrets.supabaseHost)") else {
            fatalError("Secrets.supabaseHost is not a valid host: \(Secrets.supabaseHost)")
        }
        return url
    }()

    static let supabaseAnonKey = Secrets.supabaseAnonKey

    /// Optional until Phase 2 introduces USDA food search.
    static var usdaAPIKey: String? { Secrets.usdaAPIKey }
}
