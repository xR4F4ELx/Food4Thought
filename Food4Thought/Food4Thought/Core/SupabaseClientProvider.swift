import Foundation
import Supabase

/// Single shared Supabase client.
///
/// The SDK manages its own session persistence and token refresh, so one
/// long-lived instance is correct — creating clients per request would drop
/// the refresh timer and silently sign the user out.
enum SupabaseClientProvider {
    static let shared = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey
    )
}
