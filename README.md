# curly

A native macOS app for teaching HTTP by taking a curl command apart.

![Swift 5.9+](https://img.shields.io/badge/swift-5.9%2B-orange) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)

## The teaching loop

You are sitting next to someone who has never really looked at HTTP. They open
their browser's developer tools, right-click a request and choose **Copy as
cURL**. They paste it into curly, and the wall of text becomes things they can
see and poke: a method, a web address with its parts and its query string,
headers each with a switch, cookies one per row, a body, a way of signing in.
Every section has a "?" that explains in plain English what that part of a
request is for. As they fiddle, the curl command on the right regenerates, and
the tokens that belong to whatever they are touching light up — *that* field
makes *that* bit of the command. Then they copy the command, paste it into their
terminal, and press return.

**curly never sends a request.** It is a curl *editor*, not an HTTP client. The
terminal does the sending, and that is part of the lesson: there is no magic
box, just a command you can read.

## Building and running

```bash
make test   # run the CurlKit tests
make run    # build curly.app and launch it
make app    # build curly.app, ready to double-click
```

`make app` wraps the built binary into `curly.app`, with an `Info.plist`, a
generated icon and an ad-hoc signature so macOS will run it. You need macOS 14
or later and a Swift 5.9 toolchain.

`make test` needs neither macOS nor Xcode: `CurlKit` is pure Swift with no UI
imports, so the tokenizer, parser, model and generator are testable anywhere
Swift runs.

## How it is put together

Two targets, in one SwiftPM package:

- **`CurlKit`** — a library with no UI in it at all:
  - `ShellTokenizer` splits a command line the way bash would, including
    backslash continuations, single and double quotes, and `$'…'` ANSI-C
    quoting (down to the raw UTF-8 byte escapes Firefox emits).
  - `CurlParser` turns the words into a `CurlRequest`. It handles what Chrome,
    Safari and Firefox actually copy on macOS, and anything it does not
    recognise is kept verbatim rather than dropped.
  - `CurlRequest` is a plain value type that stays faithful to what was
    written. Friendlier views of it — cookies, auth, form fields, JSON — are
    projections that read and write the underlying flags, so the Headers
    section never starts lying about what is sent.
  - `CurlGenerator` writes the request back out, and records which stretch of
    the command came from which field. That map is what drives the highlighting.
- **`curly`** — the SwiftUI app, which is a view onto one `CurlRequest`.

Two invariants hold the whole thing up, and both are tested:

```
parse(generate(model)) == model
generate(parse(command)) means what command meant
```

## Testing

Tests come first, and the parser tests are driven by real "Copy as cURL" output
checked into `Tests/Fixtures/` — Chrome, Safari and Firefox; a GET with a query
string, a POST with a JSON body and cookies, a form POST, basic auth, and some
awkward flags. The round-trip tests then push every fixture, and a pile of
deliberately horrible values, through both invariants.

```bash
make test
```

## Notes

The decisions that were not obvious are written down in
[DECISIONS.md](DECISIONS.md).
