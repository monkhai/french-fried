import Foundation

/// Values are supplied by Local.xcconfig, which is excluded from Git.
enum BackendConfiguration {
    private static func value(_ name: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: name) as? String,
              !value.isEmpty, !value.contains("$("), !value.contains("YOUR_") else {
            fatalError("Configure \(name) in Production/App/Local.xcconfig before running.")
        }
        return value
    }

    static let url: URL = {
        guard let url = URL(string: value("SUPABASE_URL")),
              url.scheme == "https", url.host != nil else {
            fatalError("SUPABASE_URL must be an HTTPS URL.")
        }
        return url
    }()
    static let publishableKey: String = {
        let key = value("SUPABASE_PUBLISHABLE_KEY")
        precondition(key.hasPrefix("sb_publishable_"), "Use a Supabase publishable client key.")
        return key
    }()
}
