# Issue #184 — Wi-Fi summary without Location Services

Audit basis: branch `codex/issue-184-wifi-location-free`, based on `origin/main`
`10005134`. This file is the P0 deliverable named by the implementation plan
(`docs/research/issue-184-wifi-without-location.md`).

Method by section: `## Current behavior (audit)` and `## Test inventory` come
from static reading of the baseline sources and tests. `## P0 capability
evidence` comes from a temporary in-process development probe on one machine,
with its own limits. `## P1 implementation` and `## Validation matrix

Status words are used per scenario. "Runtime" means the operator looked at the
patched Debug build on this machine; it is one interactive observation, not an
automated UI assertion.

| Scenario | What was checked | Result | Evidence |
| --- | --- | --- | --- |
| A. Location on, app authorized, connected | Probe identity + link fields; runtime authorized row | PASS | Probe samples 3-19 (`ssid`/`bssid` readable, RSSI/channel/PHY present); unit tests; after the later grant the operator saw the name return |
| B. Location on, app denied, connected | Probe link fields with identity unavailable | PASS | Probe samples 20-28 (`authorized` never reported; `ssid`/`bssid` false; RSSI/channel present); unit tests for the row and details |
| C. Global Location off, connected (issue core) | Probe fields; runtime row and details | PASS | Probe samples 29-58 (same link fields, identity unavailable, `locationServicesEnabled=false`); operator confirmed the row showed "已连接 + 频段/信号" with Location off |
| D. Global off, radio on, not associated | Runtime state classification | NOT RUN | Operator could not safely disconnect the only network; association classifier intentionally unchanged |
| E. Global off, Wi-Fi off | Runtime off state | NOT RUN | Same operator constraint |
| F. Ethernet primary while Wi-Fi associated | Path/primary interaction | NOT RUN | No Ethernet port was active (en0 was the default route); the Wi-Fi measurement gate still requires `connection == .wifi` and is unit-tested |
| G. Restore authorization | Same process recovers the name | PASS | Runtime: granting from the details page returned the SSID in the same process; probe samples 59-65 showed `authorizedAlways` and readable identity |
| macOS 15.7.3 (reporter) | Any of the above | NOT RUN | Not available |
| macOS 13 (minimum) | Any of the above | NOT RUN | Static contract only; no Ventura runtime |

Additional checks:

- With global Location off, the details page first showed "no networks found"
  and hid the permission entry. That was a real defect, fixed and covered by
  `PanelDetailMapperTests`; the operator then found the request entry and
  granting restored the name.
- An unauthorized scan now never runs. `WiFiNetworkScanCadenceTests` pins that
  no scan happens while denied, that a grant refreshes immediately, and that a
  later restriction clears the cached list. `PanelDetailMapperTests` pins the
  permission message for empty lists and failed scans.

Residual risk: `WiFiClassifier` still treats `serviceActive == true` plus a
connected path as associated. No tested scenario contradicted it (C behaved as
connected), but D/E were not produced and other macOS versions were not run, so
the row's `Connected`/`Not associated` wording inherits that unverified
assumption. The classifier was deliberately left unchanged because guessing a
new rule without D/E evidence would risk replacing a correct state with
"unknown".
` record
what was delivered and how it was checked. No agent changed a system privacy
setting, and no GUI was automated.

The audit sections describe the **`origin/main` `10005134` baseline**. P1
implementation changes landing in the same worktree are tracked separately; where
they diverge from the baseline, the code is authoritative.

The reported symptom: with macOS Location Services unavailable, the status
panel's Wi-Fi row shows only the permission action ("去设置中允许定位") and does
not say whether Wi-Fi is connected.


## P1 implementation (adopted)

P0 showed the data is already present without Location on macOS 27.2: only
`ssid()`/`bssid()` and scans are gated. The delivered change is therefore
mostly a presentation change, plus two details-page corrections the runtime
check exposed. It does not touch the CoreWLAN value reads, the association
classifier, the menu bar icon, or any localization resource, and it removes a
useless scan instead of adding work.

What changed:

1. **Measurements no longer require a name.** `WiFiSummaryPresentation`
   (`Sources/StatusTrioCore/UI/WiFiSummaryPresentation.swift`) now gates band
   and RSSI on `connection == .wifi` and an active state (`connected`,
   `hotspot`) instead of `summarySSID != nil`. Missing, zero, or negative-less
   values are still omitted; the 30-second RSSI cache and its invalidation rules
   are untouched.
2. **Connection state owns the summary line.** `PanelPresentationMapper.wifiSummary`
   keeps the permission prompt out of the row. When no SSID is available and no
   authorized name is still resolving, the subtitle is the existing state text
   (`Connected`, `Wi-Fi is on but not associated`, `Wi-Fi is off…`, …) joined
   with the readable `· band · RSSI` clauses through the row's existing
   `NetworkRowSubtitle` separator. The local IP still leads the line; the
   single-space placeholder while an authorized name resolves is unchanged, and
   its `measurements`/accessibility value stays `nil` so it does not describe a
   link it has not read yet.
3. **The row always opens details.** The old `StatusMappings.wifiSummaryAction`
   routing (request permission / open Location settings instead of details) is
   removed; the summary intent is `.wifiDetails`. The permission affordance is
   not lost: the Wi-Fi details page renders `wifi.permissionDenied` with a
   Location-settings intent for `denied`/`restricted`, and
   `wifi.action.requestNameAccess` with a request intent for `notDetermined`
   (pinned by `PanelDetailMapperTests`). The accessibility value keeps only the
   link facts (address, band, RSSI) because the label already carries the state;
   the visible subtitle carries both.
4. **Details: permission messages are reachable and truthful.** The detail
   mapper now checks the name permission before its generic list messages, so a
   `notDetermined`/`denied` app sees the request or Location-settings action
   instead of "no networks found" or "scan failed". This was found in the live
   check: an unauthorized CoreWLAN scan can answer with an empty list and no
   error, and the old ordering hid the permission entry. Without authorization
   the empty list never claims the range is empty.
5. **Details: no scans without permission.** `WiFiNetworkController` now asks the
   worker for link details without scanning when name access is not
   `.authorized`; it clears the cached list when permission changes and only
   schedules the 30-second periodic scan while authorized. A grant triggers an
   immediate refresh instead of waiting out the interval. The panel refresh
   button still works, but performs the permission-free read until access is
   granted. This removes pre-existing wasted scans rather than adding any.
6. **Docs.** `docs/wifi-summary.md` states the state-first behaviour and the
   scoped capability evidence.

Deliberately unchanged:

- `ssid`/`bssid` still require `.authorized`; nothing bypasses the permission
  boundary and no identity value is logged or persisted.
- `WiFiClassifier` semantics are unchanged (D/E could not be measured, so the
  association classifier keeps its existing evidence rules).
- No new polling, event types, caches, or background work; `detailsVisible`
  still decides whether an SSID/band read happens.
- No new localization keys; the composition reuses existing state strings and
  the row separator.

Tests updated or added: `WiFiSummaryTests` (measurements with a denied,
restricted, or undetermined name; zero/absent values stay unknown; inactive
states and non-Wi-Fi paths stay empty), `PanelPresentationMapperTests` (state
plus measurements under denied/restricted/notDetermined names, local-IP order,
details intent), `WiFiClassifierTests` (`denied` name access still publishes
state, RSSI, and band while `ssid` stays nil), `StatusMappingsTests` (the
now-removed action matrix is dropped; signal boundaries remain).

## Current behavior (audit)

### 1. What the monitor reads and publishes

`CoreWLANWiFiSystemReader.read(includeSSID:)`
(`Sources/StatusTrioCore/Monitoring/WiFiMonitor.swift:194-223`) reads CoreWLAN
without any scan:

| Field | CoreWLAN call | Gate | Source |
| --- | --- | --- | --- |
| power on | `interface.powerOn()` | always | WiFiMonitor.swift:208 |
| service active | `interface.serviceActive()` | always | WiFiMonitor.swift:209 |
| interface mode | `interface.interfaceMode()` | always | WiFiMonitor.swift:213 |
| RSSI | `interface.rssiValue()` | always | WiFiMonitor.swift:214 |
| SSID | `interface.ssid()` | `includeSSID` only | WiFiMonitor.swift:215 |
| band | `interface.wlanChannel()` | `includeSSID && powerOn && serviceActive` | WiFiMonitor.swift:218-220 |

`includeSSID` is the single existing "visible details" gate. It is not a
permission gate. The only caller passes `detailsVisible`
(`WiFiMonitor.swift:645`); `detailsVisible` is `isPopoverVisible`
(`Sources/StatusTrioCore/Store/SystemStatusStore.swift:1074-1077`) and defaults
to `true` (`WiFiMonitor.swift:446`, `594-602`). A read runs on one serial
utility queue (`Sources/StatusTrioCore/Monitoring/WiFiStatusReader.swift:18-34`).

Monitor classification is `WiFiClassifier.classify`
(`WiFiMonitor.swift:45-63`): `off` (radio off), `notAssociated` (service
inactive), `shared` (Internet Sharing), `temporary` (IBSS), then path-based
`hotspot` (expensive Wi-Fi path) / `noInternet` (unsatisfied path) /
`connected`. `WiFiState.isNetworkAssociated` is true for `connected`,
`noInternet`, `hotspot`, `temporary`, `shared`
(`Sources/StatusTrioCore/Models/StatusSnapshot.swift:55-62`).

Permission state comes from `CoreLocationWiFiNameAuthorizer`
(`Sources/StatusTrioCore/Monitoring/WiFiNameAuthorizer.swift`). It never calls
`CLLocationManager.authorizationStatus` on the display path: `access` starts as
`.notDetermined` and is updated only from
`locationManagerDidChangeAuthorization` (`WiFiNameAuthorizer.swift:23-35`,
`71-81`). `requestAccess()` maps `.notDetermined` to a Core Location prompt
(once) then to Location Settings, and `.denied`/`.restricted` to Location
Settings (`WiFiNameAuthorizer.swift:37-53`).

The published `WiFiStatus` (`WiFiMonitor.swift:697-705`) applies two extra
gates on top of the reader:

- `ssid = detailsVisible && nameAccess == .authorized ? normalizedSSID(...) : nil`
  (`WiFiMonitor.swift:702`)
- `band = detailsVisible && (state == .connected || state == .hotspot) ? reading.band : nil`
  (`WiFiMonitor.swift:704`)
- `rssi` is always carried when the state is associated, with a 30-second
  last-known-good cache (`WiFiMonitor.swift:701`, `1036-1054`, `487`)

The stale-read fallback repeats the SSID gate and always drops the band
(`WiFiMonitor.swift:816-821`). Result: **with `nameAccess` not `.authorized`,
`wifi.ssid` is always `nil` regardless of `detailsVisible`**, while `wifi.rssi`
still holds a real value. `wifi.band` also survives whenever the popover is
open, the state is `connected`/`hotspot`, the reader returned a band, and the
reading is fresh (the stale fallback drops it).

### 2. How the summary row resolves

`PanelPresentationMapper.wifiSummary`
(`Sources/StatusTrioCore/Presentation/Panel/PanelPresentationMapper.swift:232-318`):

1. `summarySSID` = SSID only when `connection == .wifi`, state is `.connected`
   or `.hotspot`, and `ssid` is non-empty
   (`Sources/StatusTrioCore/UI/WiFiSummaryPresentation.swift:5-10`).
2. `linkSubtitle` = band/RSSI string, and it is available **only when
   `summarySSID != nil`** (`WiFiSummaryPresentation.swift:12-32`, guard at line
   19). `rssi` is additionally suppressed unless it is negative
   (`WiFiSummaryPresentation.swift:25-27`).
3. Subtitle precedence (`PanelPresentationMapper.swift:245-261`):
   1. `summarySSID != nil` → band/RSSI, else `Connected` (or `Personal
      Hotspot` for `.hotspot`)
   2. else non-empty `ssid` (possible only when the primary connection is not
      `.wifi`) → the SSID alone
   3. else `isResolvingName` → `" "` placeholder
   4. **else associated && `.notDetermined` → "允许定位以显示 Wi-Fi 名称"
      (`wifi.action.requestNameAccess`)**
   5. **else associated && (`.denied` || `.restricted`) → "去设置中允许定位"
      (`wifi.action.openLocationSettings`)**
   6. else `wifiSubtitle(...)` → the state text
      (`PanelPresentationMapper.swift:190-210`)
4. `measurements` = optional Local IP prepended to the band/RSSI string, so it
   is `nil` whenever there is no SSID (`PanelPresentationMapper.swift:265`).
5. Title = `summarySSID ?? "Wi-Fi"` (`PanelPresentationMapper.swift:291`), so an
   unnamed connection is titled only "Wi-Fi".
6. Row click intent comes from `StatusMappings.wifiSummaryAction`
   (`Sources/StatusTrioCore/Models/StatusMappings.swift:44-55`): associated +
   `.notDetermined` → `.requestWiFiNameAccess`, associated + denied/restricted →
   `.locationSettings`, otherwise `.wifiDetails`
   (`PanelPresentationMapper.swift:281-289`).
7. Permission text is kept visible at the start of the line, ahead of the Local
   IP (`PanelPresentationMapper.swift:269-279`).
8. Accessibility label always carries the connection value
   (`wifiValue`: bars / state text, `PanelPresentationMapper.swift:169-188`,
   `292-305`); `accessibilityValue` is the measurements string or empty
   (`PanelPresentationMapper.swift:314`).
9. Symbol: `connected` shows bars from RSSI, `off`/`unavailable` show
   `wifi.slash`, `noInternet`/`notAssociated` show `wifi.exclamationmark`,
   `hotspot` shows `personalhotspot` (`PanelPresentationMapper.swift:341-355`).
   The symbol is never gated by permission.

The permission branches at lines 254-258 run **before** the state-text
fallback, require `state.isNetworkAssociated`, and do not check `connection`.
So they replace the connection state exactly for `connected`, `noInternet`,
`hotspot`, `temporary`, and `shared`.

### 3. Decision table — popover open (`detailsVisible == true`), `connection == .wifi`

`REQ` = `wifi.action.requestNameAccess`, `SET` = `wifi.action.openLocationSettings`.
"measurements" is the rendered subtitle fragment `band · RSSI`; for these rows
the subtitle is also copied into `measurements`/`accessibilityValue`.

| `WiFiState` | `WiFiNameAccess` | Title | Subtitle if no name is known (otherwise band/RSSI) | band/RSSI shown | Row click | Symbol |
| --- | --- | --- | --- | --- | --- | --- |
| connected | authorized | SSID (or "Wi-Fi" before the name arrives) | `" "` while `isResolvingName`, else `Connected` | only with SSID | `wifiDetails` | wifi bars |
| connected | notDetermined | "Wi-Fi" | `REQ` | **no** | `requestWiFiNameAccess` | wifi bars |
| connected | denied | "Wi-Fi" | `SET` | **no** | `locationSettings` | wifi bars |
| connected | restricted | "Wi-Fi" | `SET` | **no** | `locationSettings` | wifi bars |
| noInternet | authorized | SSID | `Connected` (state text is hidden even with a name) | only with SSID | `wifiDetails` | wifi.exclamationmark |
| noInternet | notDetermined / denied / restricted | "Wi-Fi" | `REQ` / `SET` | **no** | permission action | wifi.exclamationmark |
| hotspot | authorized | SSID | `Personal Hotspot` | only with SSID | `wifiDetails` | personalhotspot |
| hotspot | notDetermined / denied / restricted | "Wi-Fi" | `REQ` / `SET` | **no** | permission action | personalhotspot |
| temporary | authorized | SSID | `Connected` (state text hidden) | only with SSID | `wifiDetails` | wifi |
| temporary | notDetermined / denied / restricted | "Wi-Fi" | `REQ` / `SET` | **no** | permission action | wifi |
| shared | authorized | SSID | `Connected` (state text hidden) | only with SSID | `wifiDetails` | wifi |
| shared | notDetermined / denied / restricted | "Wi-Fi" | `REQ` / `SET` | **no** | permission action | wifi |
| notAssociated | any | "Wi-Fi" | `Wi-Fi is on but not associated` | no | `wifiDetails` | wifi (0 bars) |
| off | any | "Wi-Fi" | `Wi-Fi is off or unavailable` | no | `wifiDetails` | wifi.slash |
| unavailable | any | "Wi-Fi" | `Unable to read network status` | no | `wifiDetails` | wifi.slash |

Notes on this table:

- The reported #184 case is row 3 (or 4): the row shows "去设置中允许定位"
  instead of any connection text, has no band/RSSI, and clicking it opens
  Location Settings rather than the Wi-Fi details page. The connected state
  survives only in the symbol (bars), and in the accessibility label/value
  (`Wi-Fi, 3 格`, value empty).
- `wifi.rssi` is genuinely available in rows 2-4; it is discarded purely by the
  `summarySSID` guard in `WiFiSummaryPresentation.swift:19`.
- `wifi.band` may also be available in rows 2-4 whenever the popover is open
  and the state is `connected`/`hotspot` (`WiFiMonitor.swift:704`), but the
  display gate drops it too. Code reading cannot say whether `wlanChannel()`
  returns a band while Location Services is off; the P0 probe observed a valid
  channel and band under app-denied and global-off on macOS 27.2 only.
- Rows 13-15 (`notAssociated`, `off`, `unavailable`) never consult
  `nameAccess` for display; only the popover row click (via `wifiSummaryAction`)
  could, and it already returns `openDetails` for a non-associated state.
- `off` and `unavailable` deliberately share a symbol
  (`Tests/StatusTrioCoreTests/IconPresentationMapperTests.swift:247`).

### 4. Decision table — popover closed (`detailsVisible == false`)

- No popover row is on screen. `popupSnapshot` stops updating while closed
  (`SystemStatusStore.swift:1434-1435`).
- Every published snapshot carries `ssid == nil` and `band == nil`; `rssi` is
  still carried while associated.
- The menu bar icon is computed from `WiFiState` + `rssi` only
  (`Sources/StatusTrioCore/Presentation/Icon/IconPresentationMapper.swift:166-198`),
  so a Location-denied Mac still shows connected bars in the menu bar.
- On reopening, `setPopoverVisible(true)` sets `detailsVisible = true`, re-reads,
  and blanks the row via `isResolvingWiFiName` **only when**
  `WiFiStatus.isAwaitingName` (associated + authorized + no SSID,
  `StatusSnapshot.swift:96-103`) is true
  (`SystemStatusStore.swift:930-938`, `1465-1490`). Denied/restricted never
  takes that path.

### 5. Decision table — primary connection is not Wi-Fi

`PanelPresentationMapper.network` uses the wired row for `.ethernet` and the
Wi-Fi summary for every other value
(`PanelPresentationMapper.swift:30-48`; `.wifi` is required only for the named
form at `WiFiSummaryPresentation.swift:5-10`).

- `.offline` / `.other` / `.unknown` with a published SSID: title "Wi-Fi",
  subtitle is the bare SSID (no state, no band/RSSI)
  (`PanelPresentationMapper.swift:250-251`).
- `.offline` / `.other` / `.unknown` without a published SSID: the same
  permission/state matrix as section 3 applies (the permission branches do not
  test `connection`).
- `.ethernet`: no Wi-Fi summary at all; Wi-Fi fields are ignored for the row.

### 6. Menu bar, menus, gear, and the Wi-Fi details page

| Surface | Current behavior | Source |
| --- | --- | --- |
| Menu bar icon | `WiFiState` + RSSI bars; ignores `nameAccess`, so connected still shows bars when Location is denied | IconPresentationMapper.swift:166-198 |
| Menu bar accessibility value | `wifiValue` (`3 bars`, `No internet`, ...) inside the icon button's value | Sources/StatusTrioCore/Presentation/Accessibility/AccessibilityPresentation.swift:36-49 |
| Right-click menu | version, Check for Updates, Settings, Quit only — no Wi-Fi item | Sources/StatusTrioCore/UI/StatusMenuBuilder.swift:5-54 |
| Row gear | always opens the Wi-Fi pane (`wifiSettingsURLs`, Wi-Fi extension first) | NetworkStatusView.swift:49-60; StatusBarController.swift:1355-1360 |
| Row click | switch on `PanelSummaryIntent`; permission intents never open the details page | NetworkStatusView.swift:79-90 |
| Wi-Fi details page | only reachable through `onOpenWiFiDetails` from the summary row, i.e. only when the row intent is `.wifiDetails` | StatusPopoverView.swift:137; StatusPanelViewModel.swift:216-225 |
| Scan | only while the details page is active (`activateWiFiPanel`), plus a 30 s loop while the page stays open | SystemStatusStore.swift:948-961, 1358-1365; WiFiNetworkController.swift:304-334 |
| Details-page permission state | `permissionDenied` message + Location Settings intent; notDetermined → request action | PanelDetailMapper.swift:150-160 |
| Scan result mapping | empty list with denied/restricted → `permissionDenied`; failed scan likewise | WiFiNetworkController.swift:352-375 |

Consequence: when Wi-Fi is associated and `nameAccess` is not `.authorized`,
the Wi-Fi details page is not reachable from the popover row at all, so its
permission messages (`PanelDetailMapper.swift:150-160`) are effectively dead in
that state.

### 7. Localization strings involved

Keys (`Sources/StatusTrioCore/Localization/LocalizationKey.swift:404-431`, `443`):

- `wifi.title`, `wifi.value.*`, `wifi.subtitle.*`
- `wifi.action.requestNameAccess` = en `Allow location to show Wi-Fi name`;
  zh-Hans `允许定位以显示 Wi-Fi 名称`
- `wifi.action.openLocationSettings` = en `Allow location in Settings`;
  zh-Hans `去设置中允许定位`
- `wifi.action.openSettings`, `wifi.accessibility.withSSID`,
  `common.labelValue`, `wifi.permissionDenied`, `wifi.details.*`

Values: `Sources/StatusTrioCore/Resources/en.lproj/Localizable.strings:197-224`
and the same range in `zh-Hans.lproj`; twelve additional `.lproj` files carry
the same keys. `common.labelValue` is `"%@, %@"` in English and `"%@ %@"` in
zh-Hans, which is why the unnamed row's accessibility label reads
`Wi-Fi, 3 bars` / `Wi-Fi 3 格`.

## Test inventory

Tests that encoded this behaviour at the `origin/main` `10005134` baseline.
"Impact" states what the P1 change had to decide, not that the test was wrong.
Line numbers and names refer to the baseline; the P1 section lists what changed.

| File:line | Test | What it pins | Impact |
| --- | --- | --- | --- |
| `Tests/StatusTrioCoreTests/StatusMappingsTests.swift:16` | `testWiFiSummaryRequiresLocationPermissionBeforeOpeningAssociatedNetworkDetails` | `wifiSummaryAction`: notDetermined → request, authorized → details, denied → locationSettings, unavailable → details | Row click / intent matrix |
| `Tests/StatusTrioCoreTests/StatusMappingsTests.swift:5` | `testWiFiSignalBoundaries` | RSSI → bars thresholds | If measurements show without a name |
| `Tests/StatusTrioCoreTests/PanelPresentationMapperTests.swift:130` | `testNetworkWaitsForFreshWiFiNameAndPreservesPermissionAction` | title "Wi-Fi" + `" "` while resolving; notDetermined subtitle text and intent; denied intent | Subtitle precedence, placeholder |
| `Tests/StatusTrioCoreTests/PanelPresentationMapperTests.swift:202` | `testWiFiNamePermissionLeadsTheLocalIPAddress` | Permission text precedes Local IP in `subtitle` | Subtitle composition |
| `Tests/StatusTrioCoreTests/PanelPresentationMapperTests.swift:223` | `testWiFiLocationSettingsActionLeadsTheLocalIPAddress` | denied → Location Settings text + intent with an IP present | Permission override |
| `Tests/StatusTrioCoreTests/PanelPresentationMapperTests.swift:296` | `testNetworkSummaryUsesNamedWiFiOnlyWhenTheWiFiPathIsSelected` | Named row: title/subtitle/measurements/a11y/ intent; Ethernet ignores Wi-Fi name | Named vs unnamed summary contract |
| `Tests/StatusTrioCoreTests/WiFiSummaryTests.swift:15` | `testMeasurementsKeepMissingValuesUnknownAndRespectConnectionState` | band/RSSI formatting, missing values omitted, non-Wi-Fi connection suppresses | Whether unnamed rows may show RSSI |
| `Tests/StatusTrioCoreTests/WiFiSummaryTests.swift:36` | `testVisibleAndAccessibleMeasurementsRequireNamedActiveWiFi` | **Every** `nameAccess` value (including `.authorized`) with `ssid == nil` yields no measurements | Directly contradicts P1 "show RSSI without SSID"; must be rewritten deliberately |
| `Tests/StatusTrioCoreTests/WiFiSummaryTests.swift:58` | `testSummaryWaitsForFreshAuthorizedNameBeforePublishingMeasurements` | Waiting state suppresses measurements only while authorized + name pending | Placeholder + P1 |
| `Tests/StatusTrioCoreTests/WiFiSummaryTests.swift:95` | `testBandChangesDoNotInvalidateEitherIconOrItsSubscription` | Band equality in icon/dedup path | Low |
| `Tests/StatusTrioCoreTests/PanelPresentationTextTests.swift:108` | `testWiFiValueAndSubtitleForEveryState` | Per-state value/subtitle strings, no permission dimension | State text must stay reachable |
| `Tests/StatusTrioCoreTests/PanelPresentationTextTests.swift:150` | `testWiFiSubtitlePrefersSSID` | `wifiSubtitle` returns the SSID before the state text | Subtitle precedence |
| `Tests/StatusTrioCoreTests/PanelPresentationTextTests.swift:193` | `testStatusItemAccessibilitySummaryIncludesWiFiNameWhenAvailable` (unnamed variant: `:167 testStatusItemAccessibilitySummaryIncludesAllThreeStatuses`) | Menu bar a11y text `Wi-Fi, 3 格` vs `Wi-Fi Office, 3 格` | If unnamed rows gain text/measurements |
| `Tests/StatusTrioCoreTests/PanelDetailMapperTests.swift:133` | `testWiFiMapperPreservesSSIDIdentityGroupsActionsAndScanCapabilities` | Details rows and actions for an authorized connected state | Details page parity |
| `Tests/StatusTrioCoreTests/PanelDetailMapperTests.swift:211` | `testWiFiMapperResolvesFailureScanningPermissionAndPowerMessages` | `permissionDenied` message + Location intent; off state message | If the details page becomes reachable while denied |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:225` | `testSSIDReadsOnlyWhenDetailsAreVisible` | `includeSSID` follows `setDetailsVisible`; SSID nil when hidden | Reader gate |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:250` | `testRefreshPublishesNormalizedSSIDWhenAuthorized` | SSID published only with `.authorized` | SSID publication gate |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:265` | `testRefreshNormalizesBlankSSIDToNil` | Whitespace-only SSID → nil | Low |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:328` | `testAuthorizationChangeRefreshesAndPublishesSSID` | Grant triggers a refresh carrying the SSID | Permission transition |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:1987` | `testClosingDetailsDiscardsInFlightSSIDRead` | Visibility generation invalidation | Reader gate |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:2005` | `testPermissionChangeDiscardsInFlightRead` | Permission generation invalidation | Reader gate |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:2045` | `testFailedReadCannotRestoreCachedSSIDAfterAccessOrVisibilityChanges` | Stale fallback must not resurrect an SSID | Stale path (`WiFiMonitor.swift:816-821`) |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:2103` | `testSystemReaderBandPropagatesAndClearsWithDetailsVisibility` | Band follows `includeSSID`; band cleared when details hide | Bands are tied to `includeSSID`, not permission |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:2119` | `testFrequencyBandIsOnlyPublishedWhileDetailsAreVisible` | Published band gate includes visibility | Same |
| `Tests/StatusTrioCoreTests/WiFiClassifierTests.swift:2136` | `testUnavailableReadDoesNotReuseCachedFrequencyBand`, `...:2151 testRadioOffClearsResidualFrequencyBand` | Band is never stale | Band source-of-truth |
| `Tests/StatusTrioCoreTests/WiFiNameAuthorizerTests.swift:64` | `testReadingAccessNeverAsksCoreLocationForTheStatus` | `access` is delegate-fed, never a synchronous status read | Constrains any capability probe |
| `Tests/StatusTrioCoreTests/WiFiNameAuthorizerTests.swift:7,17,28,37,50` | request/denied/authorized/change notification tests | Request-once then Settings; delegate updates | Permission action semantics |
| `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift:1089` | `testPopoverOpeningBlanksWiFiNameUntilTheFreshNameArrives` | Authorized reopen blanks the name, then publishes | Placeholder behavior |
| `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift:1131` | `testPopoverOpeningKeepsStateTextWhenNoNameIsExpected` | No blank when `isAwaitingName` is false | Permission-row behavior |
| `Tests/StatusTrioCoreTests/SystemStatusStoreTests.swift:1179` | `testPopoverStopsWaitingForANameWhenItCloses` | Resolution cleared on close | Lifecycle |
| `Tests/StatusTrioCoreTests/StatusPanelRouteTests.swift:103` | `testWiFiDisclosureStateSurvivesReleaseAndReopensTheWiFiPage` | Wi-Fi route/disclosure state | Details-page reachability |
| `Tests/StatusTrioCoreTests/StatusMenuBuilderTests.swift:91` | `testSystemSettingsURLFallbackOrder` | Wi-Fi pane first, then Location/Network/Battery routes | Any route change |
| `Tests/StatusTrioCoreTests/LocalizationParityTests.swift:41,66` | `testEveryLanguageDeclaresExactlyTheEnglishKeys`, `testEveryLanguageKeepsTheEnglishFormatPlaceholders` | All 13 `.lproj` files share keys and placeholders | New/subtitle keys require all locales |
| `Tests/StatusTrioCoreTests/IconPresentationMapperTests.swift:220,247` | `testConnectionMappingHandlesEthernetSignalAndWiFiStateOverrides`, `testOffAndUnavailableWifiShareOneVisualState` | Icon mapping per state | Only if symbol behavior changes |

## P1 touch points and risks

P0 implications for the minimal P1 set: on macOS 27.2 the connection and signal
reads already work without Location, so P1 can stay a presentation/gating change
and does not need a new capability source. Identity (`ssid`/`bssid`) must stay
absent and must not be faked. Because D/E are `NOT RUN`, the change must remain
conservative for `notAssociated`/`off` states, and the association classifier is
out of scope by decision.

Likely touch points (code only; no proposal adopted here):

1. **Subtitle precedence / permission override** —
   `PanelPresentationMapper.swift:245-261`. This is where connection text is
   lost. Any fix must decide whether the permission action survives as text, as
   a trailing clause, or is demoted, and must keep the row useful for
   `noInternet`/`hotspot`/`temporary`/`shared` as well as `connected`.
2. **Measurements gate** — `WiFiSummaryPresentation.swift:5-32`. RSSI is already
   available without a name; band may be. Relaxing the gate to "active Wi-Fi
   connection" is the minimal way to restore `… · -58 dBm`, but it changes the
   shared contract asserted by `WiFiSummaryTests:36`, `PanelPresentationTests`
   and the accessibility value.
3. **`wifiSummaryAction` / intent** — `StatusMappings.swift:44-55`,
   `PanelPresentationMapper.swift:281-289`, `NetworkStatusView.swift:79-90`. As
   long as a permission action owns the row click, the Wi-Fi details page
   (and its scan/permission messages) stays unreachable in that state. This is
   a product decision, not just a copy change.
4. **`PanelSummaryState` shape** — `PanelSummaryState.swift:22-32` has one
   `subtitle` line and one optional `measurements` (used only as
   `accessibilityValue`). Expressing "connected + no name + permission needed"
   in one line requires an explicit ordering/grammar decision; the row is
   `lineLimit(1)` with tail truncation (`NetworkStatusView.swift:71-76`), and
   the zh-Hans permission string is long.
5. **Accessibility consistency** — `PanelPresentationMapper.swift:292-317` and
   `AccessibilityPresentation.swift:36-49` already report bars while the visual
   subtitle reports permission only. Any change should make the label, value,
   subtitle, and `measurements` agree; `Shared` tests in
   `PanelPresentationTextTests` and `StatusBarAccessibilityUpdateTests` will
   notice.
6. **`isResolvingWiFiName` blanking** — `StatusSnapshot.swift:96-103`,
   `SystemStatusStore.swift:1465-1490`. If unnamed rows start rendering a
   state/measurement line, decide whether the blank placeholder still applies
   (it currently only applies when authorized).
7. **Localization** — new or reordered copy needs `en` first and `zh-Hans`, plus
   the other eleven `.lproj` files to satisfy `LocalizationParityTests`.
   `docs/wifi-summary.md:7` currently states that permission actions stay
   visible and must be updated with the chosen behavior.
8. **Threading / blocking** — `WiFiNameAuthorizer.swift:23-27` exists because a
   synchronous `CLLocationManager.authorizationStatus` can block the main actor;
   that rule is pinned by `WiFiNameAuthorizerTests:64` and
   `docs/wifi-status-responsiveness.md`. Any capability probe or new status
   source must stay off the main actor, keep one in-flight read
   (`WiFiMonitor.swift:630-663`), and must not add polling.
9. **Band semantics** — band is currently tied to `includeSSID`
   (`WiFiMonitor.swift:218-220`) and to `connected`/`hotspot`
   (`WiFiMonitor.swift:704`). If P1 shows band without a name, that coupling
   must be split from the *authorization* gate while keeping the
   `powerOn`/`serviceActive` guard; the existing band tests then need explicit
   new cases. P0 observed a valid band with Location off on macOS 27.2; other OS
   versions are still unverified.
10. **macOS 13+ availability** — every API above exists on macOS 13
    (`CWInterface.ssid/rssiValue/wlanChannel`, `CLLocationManager`); a probe
    using anything newer needs `#available` and must keep the macOS 13 static
    contract green (`AGENTS.md`, `.agents/rules/macos-compatibility.md`). No
    Settings-pane route may become OS-version dependent
    (`.agents/rules/network.md`, `StatusMenuBuilderTests:91`).
11. **Semantics of "Location off"** — the code only knows the delegate-fed
    `CLAuthorizationStatus`. With the system master switch off and no prior
    request, the authorizer can still be `.notDetermined` until a delegate
    report arrives (`WiFiNameAuthorizer.swift:27`), which renders the *request*
    text rather than the *settings* text. P0 saw `.notDetermined` before the
    first grant and `.denied` afterwards, so both branches exist in practice;
    which one the issue reporter saw is still unknown.
12. **Idle/low-power behavior** — do not add event types, timers, or caches to
    make the row richer. `detailsVisible` still toggles reads
    (`WiFiMonitor.swift:594-602`) and the scan loop still belongs to the details
    page (`SystemStatusStore.swift:948-961`).

## P0 capability evidence

> Status vocabulary: `PASS` / `FAIL` / `BLOCKED` / `NOT RUN` per scenario. These
> results are `PASS` for *CoreWLAN capability on macOS 27.2*, not an accepted P0,
> and not a statement that the issue is fixed.

### Method and limits

- Instrumentation: a temporary development-only probe compiled into the running
  Status Trio app, sampling **inside that app process** (PID 25040). It reads
  CoreWLAN through its **own `CWWiFiClient`**, not through the production
  `CoreWLANStatusReader` serial queue and not through the monitor's
  `includeSSID` gate.
- Sampling: one sample per operator action (`trigger=launch`,
  `trigger=authorizationChange`) plus a **temporary 10-second timer** while the
  probe ran (`trigger=timer`). The timer is diagnostic only; it must be removed
  before delivery and is not a proposed poll interval.
- Privacy: the log records `ssidAvailable` / `bssidAvailable` Booleans only. No
  SSID, BSSID, password, IP address, or location value is recorded. The probe
  deliberately attempted `ssid()`/`bssid()` in every scenario
  (`identityReadAttempted=true`) so a nil return is a measured nil, not an
  un-attempted read; the plan permits this explicit development path when only
  the Boolean result is kept.
- Operator actions: the system Location Services switch and the app-level
  permission were changed **manually by the operator**; no agent toggled
  privacy settings. Original settings were restored at the end (scenario G).
- Evidence file: `/tmp/issue184-probe-evidence.log`, 65 samples. It is recorded
  here only as provenance; it is a temporary artifact and must not be committed
  or shipped.
- Not exercised: the popover was not opened during the probe, so the app-side
  `ssid`/`bandGHz` fields were always gated by `detailsVisible == false`. The
  production *display* path with the popover open is therefore still
  unverified at runtime.

### Environment

| Item | Value |
| --- | --- |
| macOS | 27.2 (build 26B123) |
| Bundle | `com.lingsmbp.StatusTrio.dev.issue-184-wifi-location-free` |
| Signing | Ad-hoc |
| Process | Status Trio app, PID 25040 |
| Wi-Fi link | interface present, radio on, service active, station mode (`interfaceMode=1`), PHY mode 6, channel 44, band raw 2 (= 5 GHz per `CWChannelBand`), noise -92 dBm |
| Probe client | independent `CWWiFiClient` in the same process |

### Scenario matrix

| Scenario | System Location | App permission | Wi-Fi | Result | Samples |
| --- | --- | --- | --- | --- | --- |
| A baseline | on | authorized | connected | PASS | 3-19 |
| B app denied | on | denied | connected | PASS | 20-28 |
| C issue core: global off | **off** | denied (unchanged) | connected | PASS | 29-58 |
| D global off + radio on, not associated | off | any | on, not associated | **NOT RUN** — operator could not disconnect safely | — |
| E global off + radio off | off | any | off | **NOT RUN** — same reason | — |
| F connected with Ethernet as primary path | off | any | associated | **NOT RUN** — no active Ethernet on this Mac | — |
| G restore authorization | on | authorized | connected | PASS | 59-65 |
| macOS 15.7.3 (issue reporter) | — | — | — | **NOT RUN** | — |
| macOS 13 (minimum supported) | — | — | — | **NOT RUN** | — |

### Capability matrix

Values are the probe's own reads, one representative sample per scenario.

| Field | A authorized | B app denied | C global off | Readable without Location? |
| --- | --- | --- | --- | --- |
| `wifiPowerOn` | true | true | true | yes |
| `wifiServiceActive` | true | true | true | yes |
| `interfaceMode` | 1 (station) | 1 | 1 | yes |
| `activePHYMode` | 6 | 6 | 6 | yes |
| `rssiDbm` | -45 … -49 | -45 … -49 | -45 … -50 | yes |
| `noiseDbm` | -92 | -92 | -92 | yes |
| `channelNumber` / `channelBandRaw` | 44 / 2 (5 GHz) | 44 / 2 | 44 / 2 | yes |
| `transmitRate` | 1729-2161 | 1441-1921 | 229-2041 | yes |
| `ssidAvailable` | **true** | **false** | **false** | **no** |
| `bssidAvailable` | **true** | **false** | **false** | **no** |
| `pathSatisfied` / `pathUsesWiFi` / `pathExpensive` | true / true / false | same | same | yes (not a Location read) |
| Probe `derivedState` (diagnostic only) | connected | connected | connected | — |
| App `WiFiStatus.state` | connected | connected | connected | — |
| App `WiFiStatus.nameAccess` | authorized | denied | denied | — |
| App `WiFiStatus.rssi` | present | present | present | — |
| App `WiFiStatus.band` | nil | nil | nil | untested — popover was closed (`detailsVisible == false`) |
| App `WiFiStatus.ssid` | absent | absent | absent | untested in A — popover closed; correctly absent in B/C |

Pre-grant observations (samples 1-2, `locationAuthorization=notDetermined`,
Location Services on): identity reads returned false while power, service,
RSSI, noise, channel, PHY, and rate were all readable. So the identity gate is
the permission state, not app launch order.

### App snapshot observations (production model, not the rendered row)

- Under B and C the production snapshot reached `state=connected`,
  `nameAccess=denied`, `rssi` present. This is exactly the input that the
  summary mapper turns into the permission-only row described in
  `## Current behavior`, so the #184 mechanism is confirmed at the data level.
  The row itself was not visually inspected in this probe.
- Under A the same snapshots carried `nameAccess=authorized` while `ssid` and
  `band` stayed nil because the popover was closed. This is consistent with
  `WiFiMonitor.swift:702,704` (`detailsVisible`) and is not evidence about
  permission gating of the band.
- Permission-state propagation lagged the system: at revoke, samples 20-21
  reported `denied` while the app still had `authorized`, and sample 22 had
  `denied` (up to two 10 s samples). At restore, sample 61 reported
  `authorizedAlways` while the app still had `denied`; sample 62 had
  `authorized` (one sample). This is delegate latency, not a defect claim.

### Representative redacted samples

```
s1  trigger=authorizationChange auth=notDetermined locEnabled=true  powerOn=true serviceActive=true mode=1 phy=6 rssi=-47 noise=-92 ch=44 bandRaw=2 rate=1921.0 ssidAvailable=false bssidAvailable=false pathSatisfied=true pathUsesWiFi=true derivedState=connected | app state=unavailable nameAccess=notDetermined rssi=nil bandGHz=nil ssid=absent
s19 trigger=timer               auth=authorizedAlways locEnabled=true  powerOn=true serviceActive=true mode=1 phy=6 rssi=-47 noise=-92 ch=44 bandRaw=2 rate=1921.0 ssidAvailable=true  bssidAvailable=true  pathSatisfied=true pathUsesWiFi=true derivedState=connected | app state=connected nameAccess=authorized rssi=-48 bandGHz=nil ssid=absent
s22 trigger=timer               auth=denied             locEnabled=true  powerOn=true serviceActive=true mode=1 phy=6 rssi=-45 noise=-92 ch=44 bandRaw=2 rate=1814.0 ssidAvailable=false bssidAvailable=false pathSatisfied=true pathUsesWiFi=true derivedState=connected | app state=connected nameAccess=denied rssi=-46 bandGHz=nil ssid=absent
s34 trigger=timer               auth=denied             locEnabled=false powerOn=true serviceActive=true mode=1 phy=6 rssi=-48 noise=-92 ch=44 bandRaw=2 rate=1921.0 ssidAvailable=false bssidAvailable=false pathSatisfied=true pathUsesWiFi=true derivedState=connected | app state=connected nameAccess=denied rssi=-47 bandGHz=nil ssid=absent
s61 trigger=authorizationChange auth=authorizedAlways locEnabled=true  powerOn=true serviceActive=true mode=1 phy=6 rssi=-47 noise=-92 ch=44 bandRaw=2 rate=1729.0 ssidAvailable=true  bssidAvailable=true  pathSatisfied=true pathUsesWiFi=true derivedState=connected | app state=connected nameAccess=denied rssi=-47 bandGHz=nil ssid=absent
s62 trigger=timer               auth=authorizedAlways locEnabled=true  powerOn=true serviceActive=true mode=1 phy=6 rssi=-47 noise=-92 ch=44 bandRaw=2 rate=1729.0 ssidAvailable=true  bssidAvailable=true  pathSatisfied=true pathUsesWiFi=true derivedState=connected | app state=connected nameAccess=authorized rssi=-47 bandGHz=nil ssid=absent
```

Probe read time across all 65 samples: 16-37 ms on the probe's own client. This
is not a measurement of the production reader's latency.

### Conclusions supported by this evidence (macOS 27.2 only)

1. `ssid()` and `bssid()` are the only Location-gated reads observed. They
   return nil when the app is `.notDetermined`, when the app is denied while the
   global switch is on, and when the global switch is off.
2. `rssiValue()`, `noise`, `wlanChannel()` (channel and band), interface mode,
   PHY mode, and transmit rate remain readable with Location denied and with the
   global switch off. **The band is therefore not an identity read on this OS.**
3. App-level denial and system-level denial are indistinguishable at the
   CoreWLAN capability layer, so the UI cannot offer two different capability
   levels.
4. The base connection state is derivable without Location: radio on + service
   active + station mode + a valid RSSI + a valid channel, plus a satisfied
   Wi-Fi path in this run. `serviceActive == true` alone still is not proof of
   association, and `NWPath.satisfied` is not "internet reachable".
5. The `#184` presentation mechanism is confirmed at the snapshot level: under
   B/C the app held `connected` + RSSI + `denied`, i.e. all it needs to show
   connection, and the permission branch is what removes it from the row.
6. This does not prove that the *product* reads or shows these fields: the probe
   bypassed the production reader, its queue, and the `includeSSID` gate, and
   the popover was never open.

### Gaps and mandatory follow-ups

- **Production linkage**: partially closed. With global Location off, the
  operator opened the patched build's popover and confirmed the Wi-Fi row showed
  the connection state together with a band and RSSI, i.e. the production reader
  and `detailsVisible` band path run under denial. Granting access from the
  details page (system prompt) then restored the SSID in the same process. This
  is one interactive observation on macOS 27.2, not an automated assertion or a
  matrix over every state.
- **Cost/idle check**: after removing the temporary 10 s timer, confirm the
  delivery adds no polling, no new event types, and no measurable idle CPU or
  wake regression; the probe's read time (16-37 ms) is not production evidence.
- **Cleanup**: delete the temporary probe path (the untracked probe source
  added for this run), the 10 s timer, and the sample log before delivery;
  verify the final diff contains no diagnostic code, no timer, and no log.
- **D/E/F**: not measured here. Without D, "radio on but not associated" and
  "cannot read association" are not runtime-verified; without E, "radio off" is
  not runtime-verified; without F, the Ethernet-primary interaction is not
  runtime-verified.
- **Other OS versions**: macOS 15.7.3 (the reporter) and macOS 13 (minimum) are
  `NOT RUN`. The macOS 13 static contract is not runtime proof.
- **Acceptance**: P0 is **not** accepted on this evidence alone. The plan's P0
  exit also needs the production-path and cleanup items above.

### Recorded decision (from the task owner, 2026-10-31)

- Because D and E could not be produced safely in this environment, a
  **conservative UI improvement may proceed without them**, as the plan allows:
  keep the connection state visible and never fabricate an association that
  cannot be read.
- The association classifier (`WiFiClassifier`) is **not** changed by this task.
  The probe's `derivedState`/`derivedReasoning` fields are diagnostics; they must
  not become product classification logic.

## Validation matrix

_To be filled by the Lead._

## Verification

Final tree: worktree branch `codex/issue-184-wifi-location-free`, uncommitted,
based on `origin/main` `10005134`; `origin/main` had advanced to `a042f9fd` by the
end of the work, so this branch was not merged or rebased.

Commands run on the final tree unless noted:

- `bash scripts/test.sh 'WiFiSummaryTests|PanelPresentationMapperTests|StatusMappingsTests|PanelDetailMapperTests|WiFiNetworkScanCadenceTests|StatusPanelViewModelTests|WiFiClassifierTests|StatusMenuBuilderTests|SystemStatusStoreTests'`
  — passed. The focused network run alone executed 171 tests with 0 failures.
- `bash scripts/verify-local.sh full` — passed: local full profile, including
  XCTest 2161 executed / 8 skipped / 0 failures, Swift Testing 797 tests in 116
  suites, Release build, non-Universal ad-hoc bundle, platform/SDK and Helper
  contracts, and the offline release simulations. The command reports UI/runtime,
  signing, notarization, DMG, release and appcast as not verified.
- `git diff --check` — clean.
- Temporary probe: compiled only into the dev build, removed from the diff; the
  raw sample log lives outside the repository (`/tmp/issue184-probe-evidence.log`)
  and is not a deliverable.

Runtime check (Debug, ad-hoc dev bundle
`com.lingsmbp.StatusTrio.dev.issue-184-wifi-location-free`, macOS 27.2 26B123,
built through `scripts/build-worktree.sh debug`):

- With global Location off, the popover row showed the connection state and
  band/RSSI (operator-confirmed), not the permission prompt.
- The details page exposed the request action; granting through the system
  prompt restored the SSID in the same process.
- No screenshots or accessibility dumps were captured; the evidence for these
  two points is the operator's report.

Cost and idle behaviour (Debug builds, popover closed, same machine, 60 s
samples taken with `ps -o %cpu`):

- Patched instance: average 0.09 % CPU (max 1.8). Two other worktree Debug
  instances running main-line code measured 0.00 % (max 0.0) and 0.21 %
  (max 3.7) in the same window. The difference is within the noise of those
  instances; no new timer, subscription, or event type was added, and the
  unauthorized scan (the expensive part) is now suppressed.
- `scripts/measure-memory.py --seconds 60` on the patched instance: RSS median
  135 MiB, physical-footprint median 51 MiB, peak 345 MiB. No baseline was
  recorded, so this is a measurement, not a regression verdict.
- Wakeups and energy were not measured (`NOT RUN`).

Not verified: D/E on this Mac, macOS 15.7.3, macOS 13 runtime, signing,
notarization, Universal packaging, release/appcast, and any other machine.


_To be filled by the Lead._
