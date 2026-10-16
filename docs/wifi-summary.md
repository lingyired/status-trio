# Current Wi-Fi summary

For an associated Wi-Fi connection with an available SSID, the summary uses the
SSID as its title and shows the current radio band and RSSI below it. Either
measurement may be absent; missing values are omitted, never replaced by zero.
If both are absent, the subtitle simply says Connected (or Personal Hotspot).
Existing permission actions remain visible when the network name is unavailable.
The technical connection panel remains available through the same disclosure.

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
The enhanced title and measurements require the primary path to be Wi-Fi,
a connected/hotspot radio, and a nonempty SSID. They are suppressed while the
primary path is Ethernet, offline, other, or unknown. VoiceOver shares the same
visibility gate, so permission prompts never announce visually hidden measurements.
A hotspot using a Wi-Fi primary path remains eligible. The existing technical
panel can still expose radio details separately from this primary-path summary.

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
