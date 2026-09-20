# Third-party notices

ApolloShell itself is MIT-licensed (see [LICENSE](LICENSE)). This file lists
bundled third-party code, the services it talks to, and design credits.

## mediaremote-adapter (bundled code)

- **Source:** https://github.com/ungive/mediaremote-adapter
- **Version:** tag `v0.7.7`, commit `e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6`
- **Where:** `extras/mediaremote-adapter/`: `src/`, `include/` and
  `bin/mediaremote-adapter.pl`, unmodified.
- **How it is used:** `scripts/build-mediaremote-adapter.sh` builds
  `MediaRemoteAdapter.framework` (arm64 + x86_64). The app bundle ships it in
  `Contents/Frameworks` and the Perl script in `Contents/Resources`. ApolloShell
  starts `/usr/bin/perl` with the script to read *now playing* information. The
  app does not link the framework.
- **License:** BSD 3-Clause, reproduced in full:

```
BSD 3-Clause License

Copyright (c) 2025, Jonas van den Berg and contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Weather data

ApolloShell requests forecasts from the one provider you choose in Nexus. The
dashboard names the source ("Weather data: …") under the data it shows. Every
request carries the User-Agent `ApolloShell/<version> (+<project URL>)`.

### Open-Meteo (default)

- https://open-meteo.com/, terms at https://open-meteo.com/en/terms
- **Data licence:** Creative Commons Attribution 4.0 (CC BY 4.0); attribution
  is required.
- **The free API is for non-commercial use only**, with limits of fewer than
  10,000 calls per day, 5,000 per hour and 600 per minute. Commercial use needs
  an Open-Meteo subscription.
- The place search in Nexus uses Open-Meteo's geocoding API under the same
  terms.

### MET Norway (api.met.no)

- https://api.met.no/, terms at https://api.met.no/doc/TermsOfService
- **Data licence:** CC BY 4.0 (and the Norwegian NLOD). Credit "MET Norway" and
  link the licence.
- **Identification is required.** Every request must carry a User-Agent that
  names the application and a way to contact its maintainers (a website or
  e-mail address). Anonymous or fake identification can get you blocked.
  ApolloShell sends the project URL. Forks should change it to their own.
- Respect the service's caching headers (`Expires`, `If-Modified-Since`) and
  the rate limits: at most 20 requests per second in total, and no polling more
  often than every 10 minutes.

### wttr.in

- https://wttr.in/, a free public service run by its open-source author, with
  no formal terms of service. Please keep requests moderate. See the service
  for where its data comes from.

## SF Symbols

The interface uses Apple's SF Symbols through the system frameworks (SwiftUI,
AppKit). The SF Symbols license lets apps show them as interface elements on
Apple platforms. They are not redistributed as files, and they are not part of
ApolloShell's app icon or any logo. The app icon is original artwork, drawn in
code by `scripts/make-icon.swift`.

## Design credit: Caelestia shell

- https://github.com/caelestia-dots/shell (GPL-3.0)
- ApolloShell's layout, panels (sidebar, dashboard, utilities, session menu,
  OSD, toasts, the Nexus settings window) and many measurements and animation
  timings follow Caelestia's design.
- The implementation is independent: Swift/SwiftUI/AppKit for macOS. No
  Caelestia source code is included.
- The animated emblem in the session menu (a planet with an orbiting moon) is
  original artwork, drawn in code in `Sources/ApolloShell/SessionEmblem.swift`.
- ApolloShell is not affiliated with or endorsed by the Caelestia project.

## Apple

macOS, Liquid Glass, SF Symbols and the names of Apple apps are trademarks of
Apple Inc. ApolloShell is not affiliated with Apple.
