# Decisions

The non-obvious calls, and why.

## The model is flag-level; the friendly views are projections

`CurlRequest` stays close to what was actually written: flags keep their
spelling (`-d` does not become `--data`), query values keep their escaping,
and a `--data-binary` body stays a `--data-binary` body. The nicer-to-use
views — cookies as rows, auth as a username and password, a form body as
fields, JSON pretty-printed — are computed on top and write back into those
same flags.

This is what lets the Auth section be friendly *and* the Headers section stay
honest: editing the password rewrites the `Authorization` header the request
already had, and you can watch it change.

## Cookies are lifted out of the headers; auth is not

A `Cookie:` header is pulled into a section of its own, because `cookie: a=1;
b=2; c=3` is the least readable line in a copied request and because each
cookie needs its own row and its own switch. The section remembers whether it
was written as a header or as `-b`, so it goes back out the way it came in.

`Authorization` stays an ordinary header row. The Auth section reads it and
writes it, but never hides it.

## Identity does not take part in equality

Every row type carries a `UUID` so SwiftUI can track it, but `==` is written by
hand over the content only. The round-trip invariant compares two models that
can never share identifiers, so including `id` would make it unprovable.

## Disabled rows are the one thing a round trip loses

`parse(generate(m)) == m` holds exactly for models with every row enabled. For
any model, `parse(generate(m)) == m.enabledOnly()` — a switched-off header is
not in the command, so it cannot come back out of one. Both forms are tested.

## Unknown flags are assumed not to take a value

When curly meets a flag it does not recognise, it has no way to know whether
the next word is that flag's argument or the URL. It assumes the flag stands
alone, which is the only guess that cannot swallow the address. `--thing=value`
carries its value with it either way, and the option catalog covers enough of
curl that the guess is rarely reached. Nothing is ever dropped: unknown flags
round-trip verbatim and are shown under "Other options" with a note saying
curly does not know them.

## Query values are stored escaped, shown decoded

The model keeps `swift%20ui`, the editor shows `swift ui`, and typing in the
editor re-escapes. An untouched value survives byte for byte; an edited one is
escaped conservatively (`%20`, never `+`).

## The generator quotes almost everything

A value is left bare only when it is a plain word — letters, digits, `.`, `-`,
`_` — so `-X POST` and `--max-time 10` stay readable while everything else is
single-quoted. Values with control characters are written with bash's `$'…'`.
This is slightly more quoting than strictly necessary, which makes each value
visibly one thing. Good for reading, good for pasting.

## The command is laid out, not echoed

Multi-line output puts the address on the first line next to `curl` and then one
flag per line, which is what browsers do. The sections are emitted in a fixed
order (address, method, headers, cookies, sign-in, body, options) rather than in
the order they were written, so two commands for the same request look the same.
Header order is not meaningful in HTTP, so nothing is lost.

## ⌘V imports, but only when it should

⌘V is bound to an import, because pasting a command is the main thing you do
with curly. If a text field is being edited, or the clipboard does not hold
something that starts with `curl`, the paste is handed back to the responder
chain and behaves normally.

## The clipboard watch is on by default

Reading the general pasteboard on macOS does not raise a privacy prompt (that
is an iOS behaviour), so the watch ships on, and it only ever shows a banner —
it never takes over the window. There is a preference in the File menu to turn
it off.

## The app target only exists on macOS

`Package.swift` adds the `curly` executable only when the manifest is evaluated
on macOS. `CurlKit` imports no UI, so `swift test` runs on Linux too, which is
where its tests were developed and are run in CI.

## The string catalog is a `.strings` file

`.xcstrings` string catalogs are compiled by Xcode, and curly is built with
SwiftPM from a `Makefile` with no Xcode project. So the catalog is a plain
`en.lproj/Localizable.strings`, generated from the source by `make strings` and
checked by a test that fails if it drifts. Every user-facing string goes through
`L("key", "English")`, so swapping in `.xcstrings` later is a mechanical change.

The generator reads the Swift source as text rather than compiling anything, so
`make strings` needs nothing but Python and works on a bare checkout. Reading
Swift with regular expressions is only safe because `StringCatalogTests`
compares the generated file against the real values at runtime, so a
misparse fails the build rather than quietly shipping the wrong English.

## Fixtures are read from disk, not bundled

`Tests/Fixtures/` keeps its readable per-browser layout and is loaded relative
to `#filePath`, rather than being moved inside the test target to become a
SwiftPM resource bundle.

## Every merge to main is a release

Rather than deciding when to cut a version, `main` ships continuously: if both
CI jobs pass, that commit becomes a GitHub release. It suits an app with one
audience and no compatibility surface, and it means the download link is never
stale.

That rules out hand-chosen version numbers, so versions are dated —
`2026.11.05.42`, the 42nd CI run, built on that day. They sort correctly, never
collide, and say something true (when this was built) instead of something
invented (how big a change it was). Re-running a build updates the release it
already made rather than failing on the existing tag.

## Send exists, but Copy is still the primary action

curly started with no networking at all, on the grounds that if the app sends
the request then the app is the thing that works and HTTP stays a black box.
That argument holds for the *ordering* of the two buttons, but not for leaving
Send out: checking one header should not need a round trip through a terminal.

So Copy is the prominent button and Send sits next to it, and the command
remains the artifact. Nothing is stored: no credential store, no history, no
session reuse, and an ephemeral `URLSession` with cookie handling switched off
so that what is sent is exactly what the command says.

## Sending is planned in CurlKit and performed in the app

`RequestPlanner` turns a `CurlRequest` into a `RequestPlan` — method, address,
headers, body, and the few flags that change how it goes out — and opens no
sockets. The app turns that plan into a `URLRequest` in about ten lines.

The split means the part that is easy to get wrong (which flags move data into
the query string, when curl adds a `Content-Type` for you, how
`--data-urlencode` escapes) is pure and tested on Linux, while the part that
cannot be unit-tested is too small to hide a bug in.

Two curl behaviours need a session delegate, because they cannot be expressed
on a `URLRequest`: `URLSession` follows redirects by default and curl does not,
so without `-L` redirects are refused; and `-k` is honoured only when asked
for, since silently accepting bad certificates would be a poor thing for a
teaching tool to do quietly.

Flags that cannot be honoured in-process — `--proxy`, `--limit-rate` and the
like — are listed in the response pane rather than ignored. Sending is a
convenience, and it says where it stops being faithful.

## Verbosity controls the command, not what the pane will let you see

The verbosity control writes curl's own `-s`, `-i` and `-v` into the command,
and a pasted command carrying one of them arrives with the setting already
made. That part was right.

What was wrong was letting it also decide what the response pane would *show*.
The reasoning at the time was that the pane should never show something the
command would not — but the response headers came back regardless of which
flags were set, and refusing to display them does not make the command more
honest, it just hides data behind a setting people do not find. The person who
asked for the verbosity control could not find the response headers behind it,
which is as clear a verdict as that design was going to get.

So the pane now has tabs — body, headers, what was sent — and all three are
always available. The honesty is kept where it belongs: when you look at
something your command would not print in a terminal, the pane says so and
offers to add the flag that would. That teaches the flag instead of enforcing
it.

## Releases are signed and notarised; pull requests are not

Release builds are signed with a Developer ID and notarised. The certificate
arrives as a base64 `.p12` in a secret, is imported into a keychain that exists
only for that run, and notarisation uses an App Store Connect API key rather
than an Apple ID and an app-specific password.

Signing is gated on `github.event_name == 'push' && github.ref ==
'refs/heads/main'`. This repository is public, so anyone can open a pull
request, and a pull request from a branch here would otherwise be handed the
certificate. Pull requests still build and package the app; theirs is ad-hoc
signed.

It runs on a GitHub-hosted runner. Nothing about `codesign` or `notarytool`
needs a particular machine, since the certificate comes out of a secret either
way, and a hosted runner has no state to leak between runs and nothing to keep
online.

The workflow degrades rather than breaking: with no signing secrets configured
it builds ad-hoc as before, and the release notes say which kind of build the
reader is downloading instead of asserting one of them.

## The text fields do not autocorrect anything

macOS substitutes curly quotes for straight ones as you type. In a letter that
is a courtesy; in a JSON body it silently stops the text being JSON, and in a
header value it sends bytes nobody meant. Every automatic substitution is
therefore switched off, in curly's own preferences domain rather than system
wide, before any window exists.

SwiftUI's `TextEditor` offers no way to say this, so the body editor is an
`NSTextView` wrapped by hand with rich text, substitutions, spelling, grammar
and data detection all turned off.

Text can still arrive already curled, pasted out of a document. curly does not
rewrite a paste behind the reader's back — it says what it found and offers a
button, and when the body is invalid JSON *because* of the quotes it says that
too. Only the quote characters are straightened: an em dash in a body is far
more likely to be the author's than the keyboard's.

## No response history, no credential storage
