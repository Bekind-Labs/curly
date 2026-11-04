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

## Fixtures are read from disk, not bundled

`Tests/Fixtures/` keeps its readable per-browser layout and is loaded relative
to `#filePath`, rather than being moved inside the test target to become a
SwiftPM resource bundle.

## No networking, no response rendering, no credential storage

Deliberately. curly writes a command down; the terminal sends it. Adding a
"Send" button would take away the reason the lesson works.
