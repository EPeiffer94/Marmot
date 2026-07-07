APP_NAME = Marmot
BUILD_DIR = .build/release
BUNDLE = $(APP_NAME).app
CONTENTS = $(BUNDLE)/Contents

.PHONY: all build bundle run clean

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(CONTENTS)/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(CONTENTS)/Resources/AppIcon.icns; fi
	codesign --force --deep --sign - $(BUNDLE)
	@echo "Built $(BUNDLE) — move it to /Applications or run: open $(BUNDLE)"

run: bundle
	open $(BUNDLE)

clean:
	rm -rf .build $(BUNDLE)
