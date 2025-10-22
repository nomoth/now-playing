APP_NAME = NowPlaying
BUNDLE_DIR = $(APP_NAME).app
CONTENTS_DIR = $(BUNDLE_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

# Compilation flags
DEBUG_FLAGS = -DDEBUG
RELEASE_FLAGS = -O
SWIFTC_FLAGS = $(if $(DEBUG),$(DEBUG_FLAGS),$(RELEASE_FLAGS))

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
	codesign --force --deep --sign - $(BUNDLE_DIR)
	
	
	@echo "App bundle created and signed: $(BUNDLE_DIR)"

clean:
	rm -rf $(BUNDLE_DIR)

run: $(BUNDLE_DIR)
	@echo "Launching $(APP_NAME)..."
	open $(BUNDLE_DIR)

test-notifications:
	@echo "Testing distributed notifications..."
	@echo "Launch Spotify and change music to see notifications"
	swift -e "import Foundation; DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(\"com.spotify.client.PlaybackStateChanged\"), object: nil, queue: nil) { notification in print(\"Notification:\", notification.userInfo ?? \"pas d'info\") }; RunLoop.main.run()"

test:
	@echo "Running unit tests..."
	./run_tests.sh

.PHONY: all clean run test-notifications test debug release