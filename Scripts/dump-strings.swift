// Prints the string-catalog entries that come from CurlKit's data (section
// explanations and per-flag explanations). Used by Scripts/make-strings.py.
import CurlKit
import Foundation

func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
}

for explanation in Explanation.allCases {
    print("\"\(explanation.key).title\" = \"\(escape(explanation.title))\";")
    print("\"\(explanation.key)\" = \"\(escape(explanation.text))\";")
}
for spec in CurlOptionCatalog.all {
    print("\"option.\(spec.long)\" = \"\(escape(spec.explanation))\";")
}
