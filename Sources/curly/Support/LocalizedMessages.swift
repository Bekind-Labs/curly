import CurlKit
import Foundation

// CurlKit has no resources and knows nothing about languages, so the sentences
// it can produce are translated here, one case at a time. Each `description`
// in CurlKit stays as the English fallback and for the tests.

extension CurlParserError {
    var localizedText: String {
        switch self {
        case .empty:
            return L("import.error.empty", "There is nothing to import.")
        case .notACurlCommand(let firstWord):
            return String(
                format: L(
                    "import.error.notCurl",
                    "This starts with “%@”, so it does not look like a curl command."
                ),
                firstWord
            )
        case .tokenizer(let error):
            return error.localizedText
        case .missingValue(let flag):
            return String(format: L("import.error.missingValue", "The flag %@ needs something after it."), flag)
        }
    }
}

extension ShellTokenizerError {
    var localizedText: String {
        switch self {
        case .unterminatedQuote(let kind):
            return String(
                format: L("import.error.unterminatedQuote", "The command ends in the middle of a %@ string."),
                kind
            )
        }
    }
}

extension RequestPlanError {
    var localizedText: String {
        switch self {
        case .noAddress:
            return L("send.error.noAddress", "There is no web address to send this to.")
        case .unreadableFile(let path):
            return String(format: L("send.error.unreadableFile", "curly could not read the file “%@”."), path)
        }
    }
}

extension RequestPlanWarning {
    var localizedText: String {
        switch self {
        case .mixedMultipart:
            return L(
                "send.warning.mixedMultipart",
                "This command mixes -F with other body flags; curly sent the -F fields."
            )
        case .unreadableCookieFile(let path):
            return String(
                format: L(
                    "send.warning.cookieFile",
                    "curly cannot read the cookie file “%@”, so no cookies were sent."
                ),
                path
            )
        case .extraAddresses:
            return L("send.warning.extraAddresses", "This command has more than one address; curly sent the first.")
        }
    }
}

extension Example {
    /// The example's name in the user's language. Its English lives in
    /// `Examples.swift` and is copied into the catalog by `make strings`.
    var localizedTitle: String {
        L("example." + id + ".title", title)
    }
}
