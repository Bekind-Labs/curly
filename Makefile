# curly — a curl editor for teaching HTTP
#
#   make test   run the CurlKit tests (works anywhere Swift runs)
#   make run    build the app and launch it
#   make app    build curly.app, ready to double-click
#
SWIFT ?= swift
CONFIG ?= release
APP := curly.app
BUILD := build
BIN = $(shell $(SWIFT) build -c $(CONFIG) --show-bin-path)

.PHONY: all test build app run clean strings icon

all: app

test:
	$(SWIFT) test

build:
	$(SWIFT) build -c $(CONFIG)

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
	@# Ad-hoc signature, so macOS is willing to run a locally built app.
	@codesign --force --sign - --timestamp=none $(APP) >/dev/null 2>&1 || \
		echo "note: could not sign $(APP); it should still run from the Finder"
	@echo "built $(APP) — double-click it, or run: open $(APP)"

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
