APP_NAME = Marmot
# Single source of truth for the version — stamped into the bundle's
# Info.plist at build time. Override per-invocation: make release VERSION=x.y.z
VERSION = 3.2.0
BUILD_NUM = $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
BUILD_DIR = .build/release
BUNDLE = $(APP_NAME).app
CONTENTS = $(BUNDLE)/Contents
RELEASE_ZIP = $(APP_NAME)-$(VERSION).zip

.PHONY: all build bundle run release clean

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(CONTENTS)/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(CONTENTS)/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUM)" $(CONTENTS)/Info.plist
	@if [ ! -f Resources/AppIcon.icns ] && [ -f Resources/AppIcon.png ]; then sh scripts/make-icon.sh; fi
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns; fi
	@for lproj in Resources/*.lproj; do \
		if [ -d "$$lproj" ]; then cp -R "$$lproj" $(CONTENTS)/Resources/; fi \
	done
	@# Embed Sparkle.framework (from the SPM artifact) for self-updates.
	@FMWK=$$(find .build/artifacts -type d -name "Sparkle.framework" 2>/dev/null | grep -m1 macos); \
	if [ -n "$$FMWK" ]; then \
		mkdir -p $(CONTENTS)/Frameworks; \
		cp -R "$$FMWK" $(CONTENTS)/Frameworks/; \
	fi
	@install_name_tool -add_rpath @executable_path/../Frameworks $(CONTENTS)/MacOS/$(APP_NAME) 2>/dev/null || true
	codesign --force --deep --sign - $(BUNDLE)
	@echo "Built $(BUNDLE) — move it to /Applications or run: open $(BUNDLE)"

run: bundle
	open $(BUNDLE)

# Distributable zip for GitHub Releases. ditto preserves the code signature
# and resource forks (plain zip can corrupt .app bundles).
release: bundle
	rm -f $(RELEASE_ZIP)
	ditto -c -k --keepParent $(BUNDLE) $(RELEASE_ZIP)
	@echo "Created $(RELEASE_ZIP) — attach it to a GitHub Release."

clean:
	rm -rf .build $(BUNDLE)
