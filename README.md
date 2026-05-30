# SwiftRDP

SwiftRDP is a native macOS RDP client prototype built with SwiftUI and FreeRDP. It is intended for Intel Macs running macOS 11 through macOS 13, where Microsoft's Windows App is not a practical RDP client option.

## Status

This project is early-stage. It has only been tested against the RDP server included with KDE Plasma so far.

## Building

Initialize the FreeRDP submodule, then build with the Makefile:

```sh
git submodule update --init --recursive
make app
```

The build targets Intel Macs running macOS 11.0 or newer and writes the app bundle to:

```sh
Build/SwiftRDP.app
```

The Makefile also builds the vendored FreeRDP dependency into `Build/install`.
