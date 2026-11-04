import CurlKit
import SwiftUI

/// Cookies get a section of their own, because "cookie: a=1; b=2; c=3" is the
/// single most impenetrable line in a copied request.
struct CookiesSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SectionCard(
            title: L("section.cookies", "Cookies"),
            explanation: .cookies,
            subtitle: subtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach($model.request.cookieSections) { $section in
                    CookieSectionView(section: $section, remove: { remove(section.id) })
                }
                AddRowButton(title: L("cookies.add", "Add a cookie")) {
                    model.request.addCookie()
                }
            }
        }
    }

    private var subtitle: String? {
        model.request.cookieSections.isEmpty
            ? L("cookies.empty", "This request carries no cookies.")
            : nil
    }

    private func remove(_ id: UUID) {
        model.request.cookieSections.removeAll { $0.id == id }
    }
}

private struct CookieSectionView: View {
    @Binding var section: CookieSection
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            HStack(spacing: 8) {
                Toggle("", isOn: $section.isEnabled)
                    .labelsHidden()
                    .help(L("row.toggle", "Include this in the request"))
                Picker("", selection: styleSelection) {
                    Text(L("cookies.asHeader", "sent as a Cookie header")).tag(0)
                    Text(L("cookies.asFlag", "sent with -b")).tag(1)
                }
                .labelsHidden()
                .fixedSize()
                .font(.caption)
                .tracksFocus(.cookieSection(section.id))
                Spacer()
                RowButton(
                    systemImage: "minus.circle",
                    help: L("cookies.removeAll", "Remove these cookies"),
                    action: remove
                )
            }

            if section.rawValue != nil {
                TrackedField(
                    prompt: L("cookies.file", "cookies.txt"),
                    text: Binding(
                        get: { section.rawValue ?? "" },
                        set: { section.rawValue = $0 }
                    ),
                    ref: .cookieSection(section.id)
                )
                Text(L("cookies.fileHint", "This is a file name, so curly leaves it alone."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($section.cookies) { $cookie in
                    CookieRow(cookie: $cookie) {
                        section.cookies.removeAll { $0.id == cookie.id }
                    }
                }
            }
        }
        .opacity(section.isEnabled ? 1 : 0.45)
        .padding(.bottom, 2)
    }

    private var styleSelection: Binding<Int> {
        Binding(
            get: {
                if case .flag = section.source { return 1 }
                return 0
            },
            set: { newValue in
                section.source = newValue == 1 ? .flag(name: "-b") : .header(name: "Cookie")
            }
        )
    }
}

private struct CookieRow: View {
    @Binding var cookie: Cookie
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $cookie.isEnabled)
                .labelsHidden()
                .help(L("row.toggle", "Include this in the request"))
            TrackedField(prompt: L("cookies.name", "name"), text: $cookie.name, ref: .cookie(cookie.id))
                .frame(width: 170)
            Text("=").foregroundStyle(.secondary)
            TrackedField(prompt: L("cookies.value", "value"), text: $cookie.value, ref: .cookie(cookie.id))
            RowButton(systemImage: "minus.circle", help: L("row.remove", "Remove this row"), action: remove)
        }
        .opacity(cookie.isEnabled ? 1 : 0.45)
    }
}
