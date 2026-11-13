# Third-party notices

JimPowerMizer is licensed under the BSD 3-Clause License (see `LICENSE`).
Release packages embed the following third-party libraries under `Libs/`. They are **not**
stored in this repository; the packager fetches them at build time (see `.pkgmeta`).

| Library | Licence | Source |
|---|---|---|
| LibStub | Public domain (stated in `LibStub.lua`) | https://www.wowace.com/projects/libstub |
| CallbackHandler-1.0 | Ace3 BSD-style licence (below) | https://www.wowace.com/projects/callbackhandler |
| Ace3 (AceAddon, AceEvent, AceTimer, AceConsole, AceDB, AceDBOptions, AceGUI, AceConfig, AceLocale) | Ace3 BSD-style licence (below) | https://github.com/WoWUIDev/Ace3 |

Rules for adding a library:
- Only embed libraries whose licence clearly allows redistribution inside another addon
  (public domain, BSD, MIT, zlib, or similar). Check the licence before adding it to `.pkgmeta`,
  and add it to this table.
- Don't embed anything marked "All Rights Reserved" or with no licence. For that reason,
  LibDataBroker-1.1 (and LibDBIcon-1.0, which needs it) are not used.
- Ace3's licence forbids redistributing a *stand-alone* copy of Ace3. Embedding it in an addon is fine.

---

## Ace3 / CallbackHandler-1.0 licence

```
Copyright (c) 2007, Ace3 Development Team 

All rights reserved.

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, 
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, 
      this list of conditions and the following disclaimer in the documentation 
      and/or other materials provided with the distribution.
    * Redistribution of a stand alone version is strictly prohibited without 
      prior written authorization from the Lead of the Ace3 Development Team. 
    * Neither the name of the Ace3 Development Team nor the names of its contributors 
      may be used to endorse or promote products derived from this software without 
      specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
