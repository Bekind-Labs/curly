import Foundation

/// Every user-facing string goes through here, so they all live in one string
/// catalog and can be translated later without touching the views. English is
/// supplied inline as the default value, which keeps the call site readable.
func L(_ key: String, _ english: String) -> String {
    NSLocalizedString(key, bundle: .module, value: english, comment: "")
}
