#!/usr/bin/env python3
"""Regenerates Sources/curly/Resources/en.lproj/Localizable.strings.

Two kinds of entry go in:

* every `L("key", "English")` call in the app's source, and
* the explanations that live as data in CurlKit — the section notes and the
  per-flag ones — read straight out of the Swift source.

Nothing here needs a toolchain or a build: it is text in, text out. The reading
of the Swift source is kept honest by StringCatalogTests, which compares the
generated file against the real values at runtime.

Run `make strings` after adding or changing a user-facing string.
"""
import glob
import pathlib
import re
import sys
import textwrap

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Sources/curly/Resources"
OUTPUT = RESOURCES / "en.lproj/Localizable.strings"

# Languages curly ships beyond English. Their files hold the translations and
# are the source of truth for them; this script only keeps the key set in step
# and flags anything whose English has moved on.
LOCALES = {"ja": "日本語", "ko": "한국어"}

NEEDS_TRANSLATION = "TODO: translate"
STALE = "STALE: the English changed since this was translated"



def unescape_swift(value):
    """A one-line Swift literal's text, with its escapes resolved."""
    return (
        value.replace("\\\\", "\x00")
        .replace('\\"', '"')
        .replace("\\n", "\n")
        .replace("\\t", "\t")
        .replace("\x00", "\\")
    )


def escape_for_catalog(value):
    """The same text, written the way a .strings file wants it."""
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )

# L("some.key", "Some English") — the two literals may sit on separate lines.
STRING = r'"((?:[^"\\]|\\.)*)"'
CALL = re.compile(r"\bL\(\s*" + STRING + r"\s*,\s*" + STRING + r"\s*\)", re.S)


def app_entries():
    entries = {}
    for path in sorted(glob.glob(str(ROOT / "Sources/curly/**/*.swift"), recursive=True)):
        with open(path, encoding="utf-8") as handle:
            for key, value in CALL.findall(handle.read()):
                entries.setdefault(key, unescape_swift(value))
    return entries


def _multiline_literal(body):
    """Reproduce a Swift \"\"\"…\"\"\" literal: dedent, and join lines whose
    predecessor ended in a backslash without a line break."""
    lines = textwrap.dedent(body).split("\n")
    out = ""
    for index, line in enumerate(lines):
        if line.endswith("\\"):
            out += line[:-1]
        else:
            out += line
            if index != len(lines) - 1:
                out += "\n"
    return out


def explanation_entries():
    """The per-section notes behind each "?" button."""
    source = (ROOT / "Sources/CurlKit/Explain/Explanations.swift").read_text(encoding="utf-8")
    entries = {}

    titles = re.search(r"var title: String \{(.*?)\n    \}", source, re.S)
    for case, title in re.findall(r"case \.(\w+): return " + STRING, titles.group(1)):
        entries["explanation.%s.title" % case] = unescape_swift(title)

    texts = re.search(r"var text: String \{(.*?)\n    \}", source, re.S)
    for case, body in re.findall(
        r'case \.(\w+):\s*\n\s*return """\n(.*?)\n\s*"""', texts.group(1), re.S
    ):
        entries["explanation.%s" % case] = _multiline_literal(body)

    if not entries:
        sys.exit("could not read any explanations out of Explanations.swift")
    return entries


def option_entries():
    """One line of English per curl flag curly recognises."""
    source = (ROOT / "Sources/CurlKit/Model/CurlOptionCatalog.swift").read_text(encoding="utf-8")
    catalog = re.search(r"static let all: \[CurlOptionSpec\] = \[(.*?)\n    \]", source, re.S)
    if not catalog:
        sys.exit("could not find the option catalog in CurlOptionCatalog.swift")

    entries = {}
    for flag, explanation in re.findall(
        r"\.init\(long: " + STRING + r".*?explanation: " + STRING, catalog.group(1), re.S
    ):
        entries["option.%s" % flag] = unescape_swift(explanation)
    if not entries:
        sys.exit("could not read any option explanations out of CurlOptionCatalog.swift")
    return entries


def read_locale(path):
    """Existing translations, as key -> (english it was translated from, text)."""
    if not path.exists():
        return {}
    entries = {}
    english = None
    comment = re.compile(r"^/\* EN: (.*) \*/$")
    line_pattern = re.compile(r"^" + STRING + r" = " + STRING + r";$")
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        matched_comment = comment.match(line)
        if matched_comment:
            english = unescape_swift(matched_comment.group(1))
            continue
        matched = line_pattern.match(line)
        if matched:
            entries[matched.group(1)] = (english, unescape_swift(matched.group(2)))
            english = None
    return entries


def write_locale(code, name, entries):
    """Rewrites one translation file: every current key, in order, each with
    the English it should be a translation of."""
    path = RESOURCES / f"{code}.lproj/Localizable.strings"
    existing = read_locale(path)

    untranslated, stale = [], []
    lines = [
        f"/* curly — {name}.",
        "   Key set maintained by `make strings`; the translations are edited by hand.",
        "   Each entry carries the English it was translated from — if that English",
        "   changes, the entry is marked and the string catalog test fails. */",
        "",
    ]
    for key in sorted(entries):
        english = entries[key]
        was, text = existing.get(key, (None, None))
        if text is None:
            untranslated.append(key)
            text = english
        elif was != english:
            stale.append(key)
        lines.append('/* EN: %s */' % escape_for_catalog(english))
        if text == english and key in untranslated:
            lines.append("/* %s */" % NEEDS_TRANSLATION)
        elif key in stale:
            lines.append("/* %s */" % STALE)
        lines.append('"%s" = "%s";' % (key, escape_for_catalog(text)))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return untranslated, stale


def main():
    entries = {}
    entries.update(explanation_entries())
    entries.update(option_entries())
    entries.update(app_entries())

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as handle:
        handle.write("/* curly — English strings.\n")
        handle.write("   Generated by `make strings`; edit the source, not this file. */\n\n")
        for key in sorted(entries):
            handle.write('"%s" = "%s";\n' % (key, escape_for_catalog(entries[key])))
    print("wrote %d strings to %s" % (len(entries), OUTPUT.relative_to(ROOT)))

    for code, name in sorted(LOCALES.items()):
        untranslated, stale = write_locale(code, name, entries)
        note = ""
        if untranslated:
            note += "  %d untranslated" % len(untranslated)
        if stale:
            note += "  %d stale" % len(stale)
        print("wrote %d strings to %s.lproj%s" % (len(entries), code, note))


if __name__ == "__main__":
    main()
