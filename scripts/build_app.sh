#!/bin/bash
set -e

# Paths
BUILD_DIR="Build/install"
SRC_DIR="SwiftRDP"
APP_NAME="SwiftRDP"

echo "Compiling..."

# 1. Compile Objective-C++ Bridge
clang++ -c "$SRC_DIR/SwiftRDPBridge/SwiftRDPBridge.mm" \
    -I"$BUILD_DIR/include/freerdp3" \
    -I"$BUILD_DIR/include/winpr3" \
    -fobjc-arc -std=c++17 -o SwiftRDPBridge.o

# 2. Compile Swift files
swiftc -c "$SRC_DIR/SwiftRDP/RDPManager.swift" \
    -I"$BUILD_DIR/include/freerdp3" \
    -import-objc-header "$SRC_DIR/SwiftRDPBridge/SwiftRDPBridge.h" \
    -o RDPManager.o

# Note: Full Swift UI compilation via command line is complex because of 
# resources, bundle structure, and code signing. 
# For a "Weekend MVP" that runs, we can compile the core logic here,
# but SwiftUI typically expects a Bundle structure.

echo "Core logic compiled. To run the full SwiftUI App, Xcode is standard."
echo "However, you have successfully compiled the FreeRDP-to-Swift engine!"
