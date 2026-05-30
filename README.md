# SwiftRDP

SwiftRDP is a native macOS RDP client prototype built with SwiftUI and FreeRDP.

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
