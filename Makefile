APP_NAME = Marmot
VERSION = 1.1.1
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
	@if [ ! -f Resources/AppIcon.icns ] && [ -f Resources/AppIcon.png ]; then sh scripts/make-icon.sh; fi
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns; fi
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
