import Foundation
import Food4ThoughtCore

protocol USDAFoodSearching: Sendable {
    /// Nil when no key is configured, so callers can tell "nothing found" from
    /// "we never asked" and say so.
    var isConfigured: Bool { get }

    func search(_ query: String) async throws -> [FoodItem]
}

/// FoodData Central search.
///
/// The key goes in the `X-Api-Key` header rather than the documented `api_key`
/// query parameter: both work, and a header keeps the key out of URLs, redirect
/// chains, and anything that logs a request line.
struct USDAFoodClient: USDAFoodSearching {
    enum Failure: LocalizedError, Equatable {
        case notConfigured
        case rateLimited
        case network
        case unexpected(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "Food search isn't set up yet. Your own foods still work."
            case .rateLimited:
                "Food search is busy. Try again in a moment."
            case .network:
                "No connection — showing your own foods only."
            case .unexpected(let reason):
                reason
            }
        }
    }

    private static let endpoint = URL(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
    private static let pageSize = 20

    /// Branded is included because it carries the barcode-scannable long tail,
    /// but it is listed last: Foundation and SR Legacy are the better-measured
    /// datasets, and FDC honours this order.
    private static let dataTypes = "Foundation,SR Legacy,Branded"

    private let apiKey: String?
    private let session: URLSession

    init(apiKey: String? = AppConfig.usdaAPIKey, session: URLSession = .shared) {
        self.apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
        self.session = session
    }

    var isConfigured: Bool { apiKey != nil }

    func search(_ query: String) async throws -> [FoodItem] {
        guard let apiKey else { throw Failure.notConfigured }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "pageSize", value: String(Self.pageSize)),
            URLQueryItem(name: "dataType", value: Self.dataTypes)
        ]

        guard let url = components?.url else {
            throw Failure.unexpected("Couldn't build the search request.")
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200...299: break
                case 429: throw Failure.rateLimited
                case 401, 403: throw Failure.notConfigured
                default: throw Failure.unexpected("Food search returned \(http.statusCode).")
                }
            }

            let decoded = try JSONDecoder().decode(USDASearchResponse.self, from: data)
            return USDAFoodMapper.items(from: decoded)
        } catch let failure as Failure {
            throw failure
        } catch is URLError {
            throw Failure.network
        } catch is DecodingError {
            throw Failure.unexpected("Food search sent something unreadable.")
        }
    }
}
