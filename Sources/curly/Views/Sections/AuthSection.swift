import CurlKit
import SwiftUI

/// Username-and-password and bearer tokens, shown as what they are. The
/// Headers section still shows the Authorization header, because that is what
/// actually goes over the wire.
struct AuthSection: View {
    @EnvironmentObject private var model: AppModel

    private enum Choice: Int, CaseIterable {
        case none, basic, bearer, other
    }

    var body: some View {
        SectionCard(
            title: L("section.auth", "Signing in"),
            explanation: .auth,
            subtitle: honestyNote
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: choice) {
                    Text(L("auth.none", "Nothing")).tag(Choice.none)
                    Text(L("auth.basic", "Username and password")).tag(Choice.basic)
                    Text(L("auth.bearer", "Token")).tag(Choice.bearer)
                    if case .otherHeader = model.request.auth {
                        Text(L("auth.other", "Something else")).tag(Choice.other)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tracksFocus(.auth)

                switch model.request.auth {
                case .basicFlag(let credentials), .basicHeader(let credentials):
                    basicFields(credentials)
                case .bearer(let token):
                    TrackedField(
                        prompt: L("auth.tokenPrompt", "token"),
                        text: Binding(
                            get: { token },
                            set: { model.request.setBearerToken($0) }
                        ),
                        ref: .auth
                    )
                case .otherHeader(let scheme, _):
                    Text(
                        String(
                            format: L("auth.otherNote", "This request signs in with “%@”, which curly shows as a plain header."),
                            scheme
                        )
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                case .none:
                    Text(L("auth.noneNote", "This request does not prove who you are."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func basicFields(_ credentials: Credentials) -> some View {
        HStack(spacing: 8) {
            TrackedField(
                prompt: L("auth.user", "username"),
                text: Binding(
                    get: { credentials.user },
                    set: { model.request.setBasicCredentials(Credentials(user: $0, password: credentials.password)) }
                ),
                ref: .auth
            )
            TrackedField(
                prompt: L("auth.password", "password"),
                text: Binding(
                    get: { credentials.password ?? "" },
                    set: { model.request.setBasicCredentials(Credentials(user: credentials.user, password: $0)) }
                ),
                ref: .auth
            )
        }
    }

    /// The whole point of this section is that it is not a secret hiding place.
    private var honestyNote: String? {
        switch model.request.auth {
        case .basicHeader:
            return L("auth.headerNote", "Written out as an Authorization header, which you can see below.")
        case .bearer:
            return L("auth.bearerNote", "Sent as “Authorization: Bearer …”, which you can see below.")
        case .basicFlag:
            return L("auth.flagNote", "curl turns -u into an Authorization header for you.")
        default:
            return nil
        }
    }

    private var choice: Binding<Choice> {
        Binding(
            get: {
                switch model.request.auth {
                case .none: return .none
                case .basicFlag, .basicHeader: return .basic
                case .bearer: return .bearer
                case .otherHeader: return .other
                }
            },
            set: { newValue in
                switch newValue {
                case .none:
                    model.request.clearAuth()
                case .basic:
                    model.request.setHeader("Authorization", to: nil)
                    model.request.credentials = Credentials(user: "", password: "")
                case .bearer:
                    model.request.credentials = nil
                    model.request.setBearerToken("")
                case .other:
                    break
                }
                model.flash(.auth)
            }
        )
    }
}
