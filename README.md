# curly

**A Mac app that takes a `curl` command apart so you can see what's in it.**

[![CI](https://github.com/Bekind-Labs/curly/actions/workflows/ci.yml/badge.svg)](https://github.com/Bekind-Labs/curly/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9+](https://img.shields.io/badge/swift-5.9%2B-orange)
![No dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

Right-click a request in your browser's developer tools, **Copy as cURL**, and
paste it into curly. The wall of backslashes becomes labelled, editable parts:
method, address, query string, headers, cookies, body, auth. Change any of them
and the command rewrites itself on the right, with the tokens you just touched
lit up — so you can see which field produces which piece of the command.

Then you copy the command back out and run it in your terminal — or press
**Send** and see the answer in a pane underneath, pretty-printed.

### [⬇ Download for macOS](https://github.com/Bekind-Labs/curly/releases/latest)

macOS 14 or later · universal (Apple silicon and Intel) · ~1.8 MB · free

Signed with Bekind Labs' Developer ID and notarised by Apple, so it opens
without a fight.

## The command is the point; Send is a convenience

curly is a curl *editor* first. **Copy** is the primary action, and the thing
you walk away with is a line of text you can read, save, paste into a ticket,
and run anywhere.

That ordering is deliberate. It was built for pairing with developers who don't
know HTTP yet, and if the app is the only thing that can run the request then
HTTP stays a black box behind someone else's UI. The command being the artifact
is what makes the lesson portable.

But round-tripping through a terminal to check one header gets old, so there is
a **Send** button too. It runs the request, shows the answer in a pane
underneath, and does its best to behave exactly as curl would — it won't follow
redirects unless the command says `-L`, and it only skips certificate checks
when the command says `-k`, which it tells you about.

The pane has tabs for the body, the response headers, and what curly sent, so
all of it is a click away. The `-s`/`-i`/`-v` setting in the editor controls
what the *command* prints in a terminal, which is a different question — when
you look at something your command wouldn't print, the pane says so and offers
to add the flag that would.

It's useful outside teaching too — any time someone hands you a forty-line
Copy-as-cURL blob and you need to find the one header that matters.

## Every part of the request is a thing you can poke

- **Method** — a popup, including custom verbs. It tells you when curl is
  inferring the method rather than being told.
- **Address** — scheme, host, port and path as separate fields, plus query
  parameters as rows. Edit the raw URL or the parts; they stay in sync both
  ways. Values are shown decoded (`swift ui`) and stored escaped (`swift%20ui`).
- **Headers** — one row each, with an *enable switch* rather than just a delete
  button, so you can turn a header off, see what breaks, and turn it back on.
- **Cookies** — the `Cookie:` header split into one row per cookie, because
  `cookie: a=1; b=2; c=3` is the least readable line in any copied request.
- **Body** — raw text, with pretty-printing and validation for JSON, and
  key/value rows for form-encoded bodies. `Content-Type` stays in step.
- **Auth** — `-u` and `Authorization: Basic …`/`Bearer …` shown as a username
  and password or a token. The Headers section still shows the real header; the
  friendly view edits it rather than hiding it.
- **Other options** — `--compressed`, `-L`, `-k` and the rest as toggles, each
  with one line of plain English. Flags curly doesn't recognise are kept exactly
  as written and shown here too. Nothing is ever silently dropped.
- **How much to show** — curl's output flags (`-s`, `-i`, `-v`) as a single
  choice, so you can set how much the command prints without remembering which
  letter does what.

curly speaks English, Japanese and Korean, following whatever your Mac is set
to. Every user-facing string lives in a catalog, including the explanations.

Nothing you type is autocorrected. macOS's curly quotes would silently stop a
JSON body being JSON, so every automatic substitution is off; if you paste text
that already has them, curly points at it and offers to straighten it.

Every section has a **?** that explains, in two or three jargon-free sentences,
what that part of an HTTP request actually is.

## It handles what browsers actually copy

The parser is driven by real "Copy as cURL" output from Chrome, Safari and
Firefox on macOS, checked into [`Tests/Fixtures/`](Tests/Fixtures). That means
multi-line commands with backslash continuations, single and double quotes,
bash `$'…'` ANSI-C quoting down to the raw UTF-8 byte escapes Firefox emits,
`--data-raw`, `--compressed`, `-b`, `-H 'cookie: …'`, `-X`, implied POST,
`-G`, `-d`/`--data-binary`/`--data-urlencode`, `-F`, `-u`, `-A`, `-e`, `-L`,
`-k`, `-I`, `--url`, and bundled short flags like `-sSLk`. 61 curl flags are
recognised in all; 49 of them carry a plain-English explanation, and the ones
that don't are preserved verbatim.

Round-tripping is a tested property, not a hope:

```
parse(generate(model)) == model
generate(parse(command)) hands curl the same arguments command did
```

The second one is checked by running both commands through a real `bash` with a
stub `curl` on `PATH` and comparing the recorded argv. That test caught `-F`
quietly coming back out as `--form`.

## Installing

Download the zip from [Releases](https://github.com/Bekind-Labs/curly/releases/latest),
unzip, drag `curly.app` to Applications, open it. It's signed and notarised,
so the only thing macOS asks is the usual "downloaded from the Internet, are
you sure?" — there's no Gatekeeper refusal to work around.

Prefer to build it yourself? It needs nothing but a Swift toolchain and takes
well under a minute:

```bash
git clone https://github.com/Bekind-Labs/curly.git
cd curly
make run
```

Each release also ships a `.sha256` next to the zip.

## Building from source

```bash
make test   # run the CurlKit tests
make run    # build curly.app and launch it
make app    # build curly.app, ready to double-click
```

`make app` wraps the binary into a bundle with an `Info.plist`, a generated
icon and an ad-hoc signature. Add `UNIVERSAL=1` for a binary that runs on both
Apple silicon and Intel, which is what releases use.

With a Developer ID to hand you can make a distributable build locally too;
this also turns on the hardened runtime and a trusted timestamp, which
notarisation requires:

```bash
make app UNIVERSAL=1 SIGN_IDENTITY="Developer ID Application: … (TEAMID)"
```

`make test` needs neither macOS nor Xcode. `CurlKit` is pure Swift with no UI
imports, so the tokenizer, parser, model and generator are testable anywhere
Swift runs — which is how the whole suite runs on Linux in CI.

## How it's put together

Two targets in one SwiftPM package, no third-party dependencies:

- **`CurlKit`** — a library with no UI in it at all.
  - `ShellTokenizer` splits a command line the way bash would.
  - `CurlParser` turns the words into a `CurlRequest`, keeping anything it
    doesn't recognise verbatim rather than dropping it.
  - `CurlRequest` is a plain value type that stays faithful to what was
    written — flags keep their spelling, query values keep their escaping. The
    friendlier views (cookies, auth, form fields, JSON) are projections that
    read and write those same flags, which is how the Auth section can be
    friendly while the Headers section stays honest.
  - `CurlGenerator` writes the request back out *and* records which stretch of
    the command came from which field. That map is what drives the highlighting.
- **`curly`** — the SwiftUI app, which is a view onto one `CurlRequest`.

`RequestPlanner` lives in `CurlKit` and works out what Send would actually put
on the wire — method, address, headers, body — as a plain value, without
opening a socket. That keeps the fiddly part (which flags change the body, what
the implied `Content-Type` is, where cookies end up) testable on Linux, and
leaves the app with a thin `URLSession` call.

Every merge to `main` that passes CI is published as a release automatically,
versioned by date: `2026.11.05.42` is that day's 42nd CI run.

The decisions that weren't obvious — and the ones you might disagree with — are
written down in [DECISIONS.md](DECISIONS.md).

## Questions you might reasonably have

**Why not Postman / Insomnia / Bruno / HTTPie?**
Those are built for people who already understand what a request *is*, and they
treat the request as something that lives inside the app. In curly the curl
command is the document: it goes in by paste and comes out by copy, and Send is
a convenience on top rather than the only way to run anything. One screen, no
accounts, no workspaces, no sync, and every section explains itself.

**Does Send behave the same as running the command?**
That's the intent, and the translation from flags to an actual request is
tested. It follows redirects only with `-L` and skips certificate checks only
with `-k`. Some flags it can't honour when sending in-process — `--proxy` and
`--limit-rate`, for instance — and rather than quietly ignoring them it lists
them in the response pane. When in doubt, copy the command and run it.

**Linux or Windows?**
The app is SwiftUI and macOS-only. `CurlKit` — the tokenizer, parser, model and
generator, which is most of the interesting code — is portable Swift with no UI
imports and its tests run on Linux in CI. A terminal or GTK front end would be a
reasonable thing to build on top.

**Is it signed?**
Release builds are signed with Bekind Labs' Developer ID and notarised by
Apple, so Gatekeeper lets them open without ceremony. Signing happens only on
a merge to `main` — pull request builds are ad-hoc signed, so a PR never gets
near the certificate.

**Does it phone home?**
No analytics, no update check, no telemetry. The only requests it ever makes
are the ones you press Send on, to the address in your own command, and nothing
about them is stored or sent anywhere else. The only thing it reads is your
clipboard, and only to offer an import — there's a preference to turn that off.

## Licence

[MIT](LICENSE).

## Contributing

Issues and pull requests are welcome. `make test` should be green, and
`make strings` regenerates the localisation catalog if you add any user-facing
text. CI runs the library tests on Linux and builds the app on macOS.
