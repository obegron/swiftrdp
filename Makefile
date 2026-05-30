# SwiftRDP Makefile

BUILD_DIR = Build/install
APP_DIR = Build/SwiftRDP.app
APP_CONTENTS_DIR = $(APP_DIR)/Contents
APP_MACOS_DIR = $(APP_CONTENTS_DIR)/MacOS
LIB_DIR = $(BUILD_DIR)/lib
INC_DIR = $(BUILD_DIR)/include/freerdp3
WINPR_INC_DIR = $(BUILD_DIR)/include/winpr3
APP_BIN = $(APP_MACOS_DIR)/SwiftRDP

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
app: engine
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

# clean removes only artifacts, not the Build/ folder itself
clean:
	rm -rf *.o $(APP_DIR)
