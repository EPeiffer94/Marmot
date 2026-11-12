APP_NAME = Marmot
# Single source of truth for the version — stamped into the bundle's
# Info.plist at build time. Override per-invocation: make release VERSION=x.y.z
VERSION = 4.1.0
BUILD_NUM = $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
BUILD_DIR = .build/release
# Built into a .noindex folder: Spotlight skips it, so development builds never
# show up in Spotlight, Launchpad or search next to the installed app.
OUT_DIR = build.noindex
BUNDLE = $(OUT_DIR)/$(APP_NAME).app
LSREGISTER = /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
CONTENTS = $(BUNDLE)/Contents
RELEASE_ZIP = $(APP_NAME)-$(VERSION).zip

.PHONY: all build bundle run release ship clean

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	@# Older builds wrote Marmot.app at the repo root; remove that copy so it stops showing in search.
	@if [ -d $(APP_NAME).app ]; then $(LSREGISTER) -u "$(CURDIR)/$(APP_NAME).app" 2>/dev/null || true; rm -rf $(APP_NAME).app; fi
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
	@# Without it the app crashes at launch, so a missing framework is fatal.
	@FMWK=$$(find .build/artifacts -type d -name "Sparkle.framework" 2>/dev/null | grep -m1 macos); \
	if [ -z "$$FMWK" ]; then \
		echo "error: Sparkle.framework not found in .build/artifacts. Run 'swift package resolve' and try again."; \
		exit 1; \
	fi; \
	mkdir -p $(CONTENTS)/Frameworks; \
	cp -R "$$FMWK" $(CONTENTS)/Frameworks/
	@install_name_tool -add_rpath @executable_path/../Frameworks $(CONTENTS)/MacOS/$(APP_NAME) 2>/dev/null || true
	codesign --force --deep --sign - $(BUNDLE)
	@# Make sure Launch Services forgets this copy if anything registered it.
	@$(LSREGISTER) -u "$(CURDIR)/$(BUNDLE)" 2>/dev/null || true
	@echo "Built $(BUNDLE) — run it with: make run (install releases with Homebrew)"

run: bundle
	open $(BUNDLE)

# Distributable zip for GitHub Releases. ditto preserves the code signature
# and resource forks (plain zip can corrupt .app bundles).
release: bundle
	rm -f $(RELEASE_ZIP)
	ditto -c -k --keepParent $(BUNDLE) $(RELEASE_ZIP)
	@echo "Created $(RELEASE_ZIP) — attach it to a GitHub Release."

# One-command release: checks, bump, build, sign, publish, Homebrew, changelog.
#   make ship            (patch)    make ship BUMP=minor    make ship BUMP=4.2.0
#   make ship DRY=1      (checks + draft release notes only)
#   make ship RESUME=1   (finish a release that stopped partway)
BUMP ?= patch
ship:
	@bash scripts/release.sh $(BUMP) $(if $(RESUME),resume,$(if $(DRY),dry,))

clean:
	@$(LSREGISTER) -u "$(CURDIR)/$(BUNDLE)" 2>/dev/null || true
	rm -rf .build $(OUT_DIR) $(APP_NAME).app
