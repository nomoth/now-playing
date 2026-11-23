APP_NAME = NowPlaying
BUNDLE_DIR = $(APP_NAME).app
CONTENTS_DIR = $(BUNDLE_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

# Same minimum as LSMinimumSystemVersion in Info.plist. Without an explicit target,
# swiftc targets the macOS version of the build machine.
MIN_MACOS = 11.0
ARCH := $(shell uname -m)

# Compilation flags
DEBUG_FLAGS = -DDEBUG
RELEASE_FLAGS = -O
SWIFTC_FLAGS = -target $(ARCH)-apple-macos$(MIN_MACOS) $(if $(DEBUG),$(DEBUG_FLAGS),$(RELEASE_FLAGS))

# Ad hoc by default. macOS ties the Spotify automation permission to the signature, and an
# ad hoc signature changes with every build: pass a stable identity to keep it (see README).
SIGN_IDENTITY ?= -

all: $(BUNDLE_DIR)

debug:
	$(MAKE) DEBUG=1 all

release:
	$(MAKE) all

$(BUNDLE_DIR): clean
	@echo "Creating app bundle..."
	mkdir -p $(MACOS_DIR)
	mkdir -p $(RESOURCES_DIR)
	
	@echo "Compiling Swift sources$(if $(DEBUG), (DEBUG mode),)..."
	swiftc $(SWIFTC_FLAGS) -o $(MACOS_DIR)/$(APP_NAME) main.swift AppDelegate.swift SpotifyMonitor.swift AppleScriptManager.swift AppConfig.swift
	
	@echo "Copying Info.plist..."
	cp Info.plist $(CONTENTS_DIR)/
	
	@echo "Copying AppleScript files..."
	cp Scripts/spotify_state.applescript $(RESOURCES_DIR)/
	
	@echo "Code signing app bundle..."
	codesign --force --sign "$(SIGN_IDENTITY)" $(BUNDLE_DIR)
	
	
	@echo "App bundle created and signed: $(BUNDLE_DIR)"

clean:
	rm -rf $(BUNDLE_DIR)

run: $(BUNDLE_DIR)
	@echo "Launching $(APP_NAME)..."
	open $(BUNDLE_DIR)

test:
	@echo "Running unit tests..."
	./run_tests.sh

.PHONY: all clean run test debug release