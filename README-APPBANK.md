# Feather AppBank 2.9.1

Preserves the AppBank catalog, certificate import names, Russian translation and AppBank updater.

- Keeps the selected installation method. A failed fully-local installation can recover using semi-local for this installation only. UserDefaults are not changed.
- Checks the local server and external manifest before handing off to iOS.
- Uses loopback on cellular networks, including IPv6-only mobile networks, instead of a cellular interface IP.
- Handles server startup errors, missing SSL files and wildcard SSL hostnames.
- Encodes nested installation URLs correctly for names containing special characters.
- Opens itms-services directly with Safari fallback; provides Retry and explicit waiting/error status.
- Polls installation progress every 250 ms instead of every 1 ms. Unavailable progress no longer implies completion.

## Attribution

Server self-check, manifest validation and direct handoff are adapted from [RyukSign](https://github.com/faroukbmiled/RyukSign), commit 844466cee6f212291913ba5216f8f19a9c016dea, created by Ryuk, GPL-3.0. Feather is created by claration. Existing copyright notices and licenses are preserved.

Semi-local uses the same public manifest services as RyukSign. IPAs remain on-device; nothing is deployed to AppBank hosting.

## Validation

GitHub Actions runs 14 regression assertions and compiles the iOS application on macOS. Device tests on Wi-Fi and mobile data are still required: compilation does not verify installd, carrier DNS, VPN behaviour or certificate validity.
