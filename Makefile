# curly — a curl editor for teaching HTTP
#
#   make test   run the CurlKit tests (works anywhere Swift runs)
#   make run    build the app and launch it
#   make app    build curly.app, ready to double-click
#
# Pass UNIVERSAL=1 to build an app that runs on both Apple silicon and Intel;
# that is what the released build uses.
#
# SIGN_IDENTITY picks the signature. The default, "-", is an ad-hoc signature:
# enough for the app to run on the machine that built it, and all a local build
# needs. Releases pass a real Developer ID, which also turns on the hardened
# runtime and a trusted timestamp, both of which notarisation requires:
#
#   make app UNIVERSAL=1 SIGN_IDENTITY="Developer ID Application: … (TEAMID)"
#
SWIFT ?= swift
CONFIG ?= release
APP := curly.app
BUILD := build
SIGN_IDENTITY ?= -

ifeq ($(UNIVERSAL),1)
ARCH_FLAGS := --arch arm64 --arch x86_64
else
ARCH_FLAGS :=
endif

BIN = $(shell $(SWIFT) build -c $(CONFIG) $(ARCH_FLAGS) --show-bin-path)

.PHONY: all test build app run clean strings icon

all: app

test:
	$(SWIFT) test

build:
	$(SWIFT) build -c $(CONFIG) $(ARCH_FLAGS)

## Wraps the built binary into a double-clickable application bundle.
app: build icon
	$(RM) -r $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN)/curly $(APP)/Contents/MacOS/curly
	@# The SwiftPM resource bundle carries the string catalog.
	@if [ -d "$(BIN)/curly_curly.bundle" ]; then \
		cp -R "$(BIN)/curly_curly.bundle" $(APP)/Contents/Resources/; \
	fi
	cp Scripts/Info.plist $(APP)/Contents/Info.plist
	cp $(BUILD)/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	@printf 'APPL????' > $(APP)/Contents/PkgInfo
ifeq ($(SIGN_IDENTITY),-)
	@# Ad-hoc signature, so macOS is willing to run a locally built app.
	@codesign --force --sign - --timestamp=none $(APP) >/dev/null 2>&1 || \
		echo "note: could not sign $(APP); it should still run from the Finder"
	@echo "built $(APP) (ad-hoc signed) — double-click it, or run: open $(APP)"
else
	@# A real Developer ID. --options runtime and a timestamp are both required
	@# before Apple will notarise the result. No --deep: the only thing nested
	@# in the bundle is a resource bundle with no code in it.
	codesign --force --options runtime --timestamp \
		--sign "$(SIGN_IDENTITY)" $(APP)
	codesign --verify --strict --verbose=2 $(APP)
	@echo "built $(APP), signed as $(SIGN_IDENTITY)"
endif

run: app
	open $(APP)

## Renders the icon. Needs macOS (AppKit for the drawing, sips and iconutil).
icon: $(BUILD)/AppIcon.icns

$(BUILD)/AppIcon.icns: Scripts/make-icon.swift
	mkdir -p $(BUILD)/AppIcon.iconset
	$(SWIFT) Scripts/make-icon.swift $(BUILD)/icon.png
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size $(BUILD)/icon.png \
			--out $(BUILD)/AppIcon.iconset/icon_$${size}x$${size}.png >/dev/null; \
		double=$$(($$size * 2)); \
		sips -z $$double $$double $(BUILD)/icon.png \
			--out $(BUILD)/AppIcon.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns $(BUILD)/AppIcon.iconset -o $(BUILD)/AppIcon.icns

## Regenerates the English string catalog from the source.
strings:
	python3 Scripts/make-strings.py

clean:
	$(RM) -r .build $(BUILD) $(APP)
