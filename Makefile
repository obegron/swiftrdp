# SwiftRDP Makefile

BUILD_DIR = Build/install
APP_DIR = Build/SwiftRDP.app
APP_CONTENTS_DIR = $(APP_DIR)/Contents
APP_MACOS_DIR = $(APP_CONTENTS_DIR)/MacOS
APP_RESOURCES_DIR = $(APP_CONTENTS_DIR)/Resources
LIB_DIR = $(BUILD_DIR)/lib
INC_DIR = $(BUILD_DIR)/include/freerdp3
WINPR_INC_DIR = $(BUILD_DIR)/include/winpr3
APP_BIN = $(APP_MACOS_DIR)/SwiftRDP
ICON_PNG = Assets/SwiftRDPIcon.png
ICONSET_DIR = Build/SwiftRDPIcon.iconset
APP_ICON = $(APP_RESOURCES_DIR)/SwiftRDP.icns

# Compiler and Flags
MACOS_TARGET = 11.0
ARCH = $(shell uname -m)
CC = clang
CXX = clang++
SWIFTC = swiftc
MACOS_FLAGS = -mmacosx-version-min=$(MACOS_TARGET)
SWIFT_TARGET = -target $(ARCH)-apple-macosx$(MACOS_TARGET)

INC_FLAGS = -I. -I$(INC_DIR) -ISwiftRDP/SwiftRDPBridge -I$(WINPR_INC_DIR)
CFLAGS = $(INC_FLAGS) $(MACOS_FLAGS)
# Link against OpenSSL and FFmpeg as required by FreeRDP
LDFLAGS = -L$(LIB_DIR) -L$(LIB_DIR)/freerdp3 -L/usr/local/opt/openssl@3/lib -L/usr/local/opt/ffmpeg/lib \
          -lfreerdp3 -lfreerdp-client3 -lwinpr3 \
          -lremdesk-common -lrdpsnd-common \
          -lssl -lcrypto -lavcodec -lavutil -lswscale -lswresample -lz \
          -framework Foundation -framework CoreGraphics -framework CoreServices -framework Security \
          -framework AVFoundation -framework AudioToolbox -framework AudioUnit -framework CoreAudio -lc++

# 'all' depends on 'engine' being built first
all: engine app

# engine triggers the script
engine:
	./scripts/build_freerdp.sh

# app depends on engine being present
app: engine $(APP_ICON)
	@mkdir -p $(APP_MACOS_DIR)
	@cp SwiftRDP/Info.plist $(APP_CONTENTS_DIR)/Info.plist
	@echo "Compiling Bridge..."
	$(CXX) -c SwiftRDP/SwiftRDPBridge/SwiftRDPBridge.mm $(CFLAGS) -fobjc-arc -std=c++17 -o SwiftRDPBridge.o
	@echo "Compiling Swift App..."
	$(SWIFTC) -parse-as-library -o $(APP_BIN) \
		$(SWIFT_TARGET) \
		SwiftRDP/SwiftRDP/RDPManager.swift \
		SwiftRDP/SwiftRDP/ConnectionProfile.swift \
		SwiftRDP/SwiftRDP/ConnectionSettings.swift \
		SwiftRDP/SwiftRDP/KeychainPasswordStore.swift \
		SwiftRDP/SwiftRDP/main.swift \
		SwiftRDP/UI/RDPApp.swift \
		SwiftRDP/UI/ContentView.swift \
		SwiftRDP/UI/RemoteDesktopView.swift \
		SwiftRDP/UI/MetalView.swift \
		SwiftRDP/UI/SecurePasswordField.swift \
		SwiftRDPBridge.o $(INC_FLAGS) -import-objc-header SwiftRDP/SwiftRDPBridge/SwiftRDPBridge.h $(LDFLAGS) -framework SwiftUI -framework AppKit -framework Metal -framework MetalKit

$(APP_ICON): $(ICON_PNG)
	@mkdir -p $(ICONSET_DIR) $(APP_RESOURCES_DIR)
	sips -z 16 16 $(ICON_PNG) --out $(ICONSET_DIR)/icon_16x16.png
	sips -z 32 32 $(ICON_PNG) --out $(ICONSET_DIR)/icon_16x16@2x.png
	sips -z 32 32 $(ICON_PNG) --out $(ICONSET_DIR)/icon_32x32.png
	sips -z 64 64 $(ICON_PNG) --out $(ICONSET_DIR)/icon_32x32@2x.png
	sips -z 128 128 $(ICON_PNG) --out $(ICONSET_DIR)/icon_128x128.png
	sips -z 256 256 $(ICON_PNG) --out $(ICONSET_DIR)/icon_128x128@2x.png
	sips -z 256 256 $(ICON_PNG) --out $(ICONSET_DIR)/icon_256x256.png
	sips -z 512 512 $(ICON_PNG) --out $(ICONSET_DIR)/icon_256x256@2x.png
	sips -z 512 512 $(ICON_PNG) --out $(ICONSET_DIR)/icon_512x512.png
	sips -z 1024 1024 $(ICON_PNG) --out $(ICONSET_DIR)/icon_512x512@2x.png
	iconutil -c icns $(ICONSET_DIR) -o $(APP_ICON)

# clean removes only artifacts, not the Build/ folder itself
clean:
	rm -rf *.o $(APP_DIR) $(ICONSET_DIR)
