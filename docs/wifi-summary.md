# Current Wi-Fi summary

For an associated Wi-Fi connection with an available SSID, the summary uses the
SSID as its title and shows the current radio band and RSSI below it. Either
measurement may be absent; missing values are omitted, never replaced by zero.
If both are absent, the subtitle simply says Connected (or Personal Hotspot).
The technical connection panel remains available through the same disclosure.

When the network name is unavailable, the row keeps describing the connection.
The title stays Wi-Fi and the subtitle shows the connection state (Connected,
Not associated, Off, No internet, and so on) followed by any band and RSSI the
radio still reports. A missing name never replaces that state: no
location-permission prompt occupies the summary line, and clicking the row
always opens the Wi-Fi details. The detail page owns the explicit action that
requests location access or opens Location settings, so the permission route
stays reachable one level in. On the tested macOS 27.2 machine, the app process
read RSSI and the channel band with global Location Services disabled, and the
popover rendered them; SSID/BSSID stayed unavailable and scanning needs the
permission. A separate in-process probe also saw noise, PHY mode and transmit
rate, which the summary does not display. This is evidence for this machine and
these states only, not for other macOS versions, and not for the
not-associated/radio-off states. Valid measurements may appear without a name;
missing or zero RSSI remains unknown, subject to the existing bounded cache. See
[the capability evidence and remaining gaps](research/issue-184-wifi-without-location.md).

`CoreWLANWiFiSystemReader` reads
[`CWInterface.wlanChannel()`](https://developer.apple.com/documentation/corewlan/cwinterface/wlanchannel())
only behind its existing visible-details gate, and only while Wi-Fi power and
service are active. It maps known `CWChannelBand` values; unknown values remain
nil. The call runs on the existing serial utility queue introduced for Wi-Fi
status reads. It does not call `scanForNetworks`, request authorization, probe
Internet servers, or change the polling interval. RSSI already comes from this
reader. Neither measurement is Internet speed or a test of Internet reachability.

Closing details, a disconnected/off state, or a failed fresh reading drops the
frequency band. A momentarily invalid RSSI (CoreWLAN `rssiValue()` returns `0`
or nothing while the interface is still associated, as reported in issue #110)
is bridged: the last known-good value is reused for up to 30 seconds, reuse
never extends that window, and any association change (join, roam, leave, radio
toggle) drops the cache so a previous network's strength is never shown. A
link-quality event's RSSI seeds the same cache. An associated interface with no
known reading renders at full contrast instead of a faded, disabled glyph.
The enhanced title and the measurements require the primary path to be Wi-Fi and
a connected/hotspot radio. The SSID title additionally requires a name, but the
measurements do not: without Location access the row still shows the connection
state with the readable band and RSSI. Both are suppressed while the primary path
is Ethernet, offline, other, or unknown. VoiceOver's value carries the address,
band and signal, while its label already names the state. A hotspot using a Wi-Fi
primary path remains eligible. The association state itself still comes from the
existing classifier (radio power, service state, interface mode, network path);
this change did not alter or re-verify that rule, and the not-associated and
radio-off states were not exercised on the test machine.

Suppressing them on Ethernet is not the section going blank: the row is the
network section's single slot, and a wired primary path hands it to the wired row,
which reports the same five technical rows with the LAN address. See
[wired link status](ethernet-link-status.md).

The optional band is omitted from `MenuBarStatus`. Both icon subscriptions project
to this lightweight status before deduplication, and neither menu-bar nor Dock
render keys change when only the band changes. The full popover snapshot retains
the band for display. Twelve localizations share standard GHz/dBm unit labels;
frequency numbers use the selected locale's decimal formatting.

## Location permission recovery

The first explicit permission click requests macOS authorization. If a request
was already made in this process and authorization is still undetermined, the
next click opens Location Services in System Settings instead of repeatedly
issuing the same request. Denied or restricted access also routes to Settings;
if access was granted while the displayed status was stale, the click refreshes
the Wi-Fi reading. Startup never requests permission automatically.

Every Wi-Fi reading checks name access on the main actor, so that check reads
the status Core Location last reported to the authorizer's delegate. Asking
`CLLocationManager.authorizationStatus` directly can wait synchronously for
`locationd`, and a stuck `locationd` then froze the whole app. Until the first
report arrives, name access is treated as undetermined.

Native macOS uses `NSLocationUsageDescription`; the app also retains its existing
`NSLocationWhenInUseUsageDescription`. Both are present in the app plist and all localized
`InfoPlist.strings`; packaging rejects a missing or empty value in the final
bundle. See Apple's [authorization requirements](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services).

Permission persistence across updates is separate from this recovery flow.
Ad-hoc signatures identify a particular build, so privacy grants may not carry
across an update. Stable signing identity is needed for reliable cross-version
identity, with Developer ID being the distribution path outside the App Store.
This change does not provide a signing certificate or
reset the user's privacy database. See Apple's [code identity documentation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
