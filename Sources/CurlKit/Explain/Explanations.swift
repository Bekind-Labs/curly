import Foundation

/// The plain-English notes behind every "?" button.
///
/// They live here rather than in the views so they can be tested and reused,
/// and so the app layer only has to worry about looking them up in its string
/// catalog. Written for somebody who has never seen HTTP: no word is used
/// before it is explained.
public enum Explanation: String, CaseIterable, Sendable {
    case request
    case method
    case url
    case query
    case headers
    case cookies
    case body
    case json
    case formBody
    case contentType
    case auth
    case otherOptions
    case output

    /// The key to look up in the app's string catalog.
    public var key: String { "explanation.\(rawValue)" }

    public var title: String {
        switch self {
        case .request: return "The request"
        case .method: return "Method"
        case .url: return "Web address"
        case .query: return "Query string"
        case .headers: return "Headers"
        case .cookies: return "Cookies"
        case .body: return "Body"
        case .json: return "JSON"
        case .formBody: return "Form fields"
        case .contentType: return "Content-Type"
        case .auth: return "Signing in"
        case .otherOptions: return "Other options"
        case .output: return "The curl command"
        }
    }

    /// One to three sentences, in English, shipped as the default value.
    public var text: String {
        switch self {
        case .request:
            return """
            A request is one message your computer sends to a website, asking it \
            to do something. Everything below is a part of that message. curly \
            only writes the message down — your terminal is what actually sends it.
            """
        case .method:
            return """
            The method is the verb of the request: it says what you want done. \
            GET means "give me this", POST usually means "here is something new", \
            PUT and PATCH mean "change this", and DELETE means what it says.
            """
        case .url:
            return """
            The web address says which machine to talk to and which thing on it \
            you want. It is made of a scheme (https), a host (api.example.com), \
            sometimes a port number, and a path (/v1/items).
            """
        case .query:
            return """
            The query string is the part of the address after the "?". It is a \
            list of name-and-value pairs, joined by "&", used for things like \
            search terms and page numbers. Spaces and other awkward characters \
            get written as %20 and friends so they survive the trip.
            """
        case .headers:
            return """
            Headers are extra lines of information attached to the request, like \
            the label on a parcel. They say things like what kind of answer you \
            can accept and what software is asking. Switch one off to see what \
            the site does without it.
            """
        case .cookies:
            return """
            Cookies are small notes a website asked your browser to keep and hand \
            back on every visit. They are how a site remembers that you are \
            signed in. They travel in a single header, one note after another.
            """
        case .body:
            return """
            The body is the content you are sending along with the request — the \
            parcel rather than the label. GET requests usually have none; POST \
            and PUT usually do.
            """
        case .json:
            return """
            JSON is a common way of writing structured data as text, using \
            braces for objects and square brackets for lists. Most web APIs \
            expect it. If it is laid out neatly here, it still arrives as one \
            long line.
            """
        case .formBody:
            return """
            A form body is a list of name-and-value pairs, written the same way \
            as a query string: name=value, joined by "&". It is what an ordinary \
            web page form sends when you press a button.
            """
        case .contentType:
            return """
            Content-Type is the header that tells the server what kind of thing \
            is in the body, so it knows how to read it — JSON, form fields, \
            plain text, a file, and so on.
            """
        case .auth:
            return """
            This is how the request proves who you are. A username and password \
            get scrambled into one Authorization header; a token is sent in that \
            same header after the word "Bearer". Either way it is just a header, \
            which is why you can still see it in the Headers section.
            """
        case .otherOptions:
            return """
            These are curl's own settings rather than parts of the request: how \
            to handle redirects, whether to unzip the answer, how long to wait. \
            Anything curly does not recognise is kept here untouched so nothing \
            is lost.
            """
        case .output:
            return """
            This is the finished command. Copy it, paste it into your terminal, \
            and press return to actually send the request. Edit anything on the \
            left and watch the matching part here change.
            """
        }
    }
}
