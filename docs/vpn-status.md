# VPN row

The popup's VPN row reports whether traffic is being relayed: through a tunnel,
through a system VPN service, or through the system-wide proxy. It is a popup
row only — nothing in the menu bar or the Dock icon draws it, and it is not part
of `StatusSnapshot`.

## The three signals

| Signal | Source | What it means |
| --- | --- | --- |
| Tunnel interface | `getifaddrs()`, names matching `utun`/`ppp`/`ipsec`/`tap`/`tun` that are `IFF_UP` and hold a routable IPv4 address | A tunnel is carrying traffic. Covers every client that creates a virtual interface: WireGuard, Tailscale, OpenVPN, and Clash in TUN mode. |
| System VPN service | `SCNetworkServiceCopyAll` plus `SCNetworkConnectionGetStatus`, for services whose interface type is PPP, IPSec or L2TP | A VPN configured in System Settings is connected. Supplies the name the row leads with. |
| System-wide proxy | `State:/Network/Global/Proxies` through `SCDynamicStoreCopyValue` | A proxy is set. Not a tunnel — no virtual interface, no new address — so it is reported separately and never reads as a connected VPN. |

Mihomo/Clash Verge service mode exposes a local owner-only Unix control
socket. `GET /configs` is read-only and reports `tun.enable` plus the concrete
`tun.device`; when that device matches an active tunnel interface, the row is
labelled **Clash Verge TUN**. This attribution requires no helper, root,
Accessibility or Input Monitoring grant, and no secret on the local socket.
If the socket is absent, the row falls back to **TUN**. The read is
demand-driven while the VPN row is visible. The same row offers a power glyph
for the attributed TUN: an explicit click sends the public Mihomo
`PATCH /configs` body `{"tun":{"enable":false}}` (or `true`), re-reads
`/configs` to confirm the device and state, and shows a localized failure if
the request is rejected or the readback disagrees. The device is revalidated
through `expectedDevice` inside the client so a stale row cannot toggle a
different client's TUN. Actual toggle behavior on this Mac remains **NOT RUN**
until the user exercises the control.

A system VPN service leads with its service name and reads **Connected**. A
bare tunnel that has no system service is labelled **TUN** (never **VPN**),
because it is detected but not a controllable system VPN service. A proxy alone
reads **System proxy** with its endpoint as the detail; neither reads **Not
connected**. When a tunnel and proxy are both up, the detail carries them
together (`Connected · proxy 127.0.0.1:10808`).

## Why an address and not a name list

macOS keeps its own tunnels up. Measured on macOS 26.6.1, with Clash Verge in
system-proxy mode:

```
utun0 up=true flags=32849 v4=[]
utun1 up=true flags=32849 v4=[]
utun2 up=true flags=32849 v4=[]
utun3 up=true flags=32849 v4=[]
```

All four are `UP,RUNNING` and none carries an IPv4 address, while a tunnel that
is forwarding traffic has one. That is the property
`TunnelInterfaceClassifier.isActiveTunnel` keys on. A hard-coded list of system
interface names would need maintaining on every macOS release and would still
miss a new one; the address is what separates a tunnel carrying traffic from a
tunnel that is merely present.

## Power control (#272)

The summary row now has one power glyph when the system exposes a configured
System Settings VPN service. The target is the first service in
`SCNetworkServiceCopyAll` order when disconnected. When any service reports
connected or connecting, the switch targets that service instead, so turning it
off cannot stop a different, disconnected first entry. The service ID, not its
display name, is passed to `SCNetworkConnectionCreateWithServiceID`.

The switch is **absent** when there is no configured service. A system proxy
alone never creates a service and never shows a switch; a third-party
NetworkExtension tunnel that only creates a `utun` is likewise read-only. It is
disabled while a request is in flight, while SystemConfiguration reports
`connecting`/`disconnecting`, or when the selected service is disabled. A
failed start/stop, a rejected request, and a callback timeout each produce a
short localized row message; the monitor is re-read even after a timeout so the
row returns to the real system state.

`SCNetworkConnectionStart`/`Stop` return values only acknowledge the request.
The row leaves its changing state when the status callback reports the target
state, or after a bounded 20-second timeout. The connection uses `linger: true`
for a user-initiated connect, so closing the popover does not tear down a VPN
the user just started. Stop uses `forceDisconnect: false`; if another client
keeps the service connected, the timeout reports that the result was not
confirmed rather than claiming a disconnect. No privileged helper, entitlement,
`scutil` subprocess, private API, or admin network-preference write is used.

The documented SystemConfiguration control surface only guarantees PPP
services. IPSec/L2TP/IKEv2 services that appear in the service reader are shown
with the same switch, but actual control on each OS build remains an evidence
item (`NOT RUN` in automated tests). NetworkExtension configurations owned by
another app are not system services and are outside the switch.

## Known limitations

- **A system proxy is not a VPN.** Clash Verge in system-proxy mode sets
  `HTTPEnable`, `HTTPSEnable` and `SOCKSEnable` on `127.0.0.1:10808` and creates
  no tunnel. The row reports it as a proxy. Only TUN mode produces a `utun` with
  an address.
- **iCloud Private Relay** does not report as a VPN either. Whether it holds an
  address on a system `utun` has not been observed on this machine; if a report
  comes in, the place to extend is `TunnelInterfaceClassifier`, with the
  observed interface as the evidence.
- **The service name needs an admin account.** macOS treats the network
  preferences as administrative. On this machine (admin, macOS 26.6.1)
  `SCNetworkServiceCopyAll` returns the seven configured services without sudo.
  A standard account can be refused the list; the row then reads **Connected**
  without a name. The name is decoration and the verdict does not depend on it —
  that is why the service signal is not the primary one.
- **VPN services have no Settings pane of their own.** They live in the Network
  pane's service list, so the row is not a button and offers no gear. See
  [System Settings pane routes](settings-pane-routes.md): the first route
  decides the destination and a wrong one is never corrected.
- **No NetworkExtension.** `NEVPNManager` would name the VPN precisely, but it
  needs the `com.apple.developer.networking.networkextension` entitlement and a
  provisioning profile, and this repository signs Ad-hoc with no Developer ID.
  SystemConfiguration needs no entitlement, no `Info.plist` entry and no TCC
  grant — the same reason the Wi-Fi and Bluetooth rows avoid entitlements.
- **The read runs on the main actor.** One read is a `getifaddrs` pass plus two
  SystemConfiguration lookups, measured in single-digit milliseconds, and the
  monitor is driven by the store's fallback tick rather than a per-frame path.

## Default state

`.vpn` is in `SettingsStore.defaultEnabledPopupSections`, so a fresh install
shows the row. A user who has already saved a section list is covered by a
one-shot migration: `sanitizedEnabledPopupSections(_:hasIntroducedVPN:)` adds the
row when the `vpnPopupSectionIntroduced.v1` marker is unset, and the result is
written back to `UserDefaults` because `didSet` does not run for an assignment
made inside `init`. After that the stored list is the user's own choice, so
switching the row off sticks.

## Where the code lives

| File | Role |
| --- | --- |
| `Models/VPNStatus.swift` | `VPNStatus`, `VPNProxyStatus`, `VPNProbeReading`, `VPNStatusResolver`, `TunnelInterfaceClassifier`, and `VPNServiceReading` identity/state |
| `Monitoring/VPNProbe.swift` | The three readers and their protocols; the service reader keeps service IDs and connection states |
| `Monitoring/VPNMonitor.swift` | Lifecycle, the `SCDynamicStore` subscription, the stream |
| `VPN/VPNPowerController.swift` | One in-flight start/stop request, failure copy, refresh and bounded state |
| `VPN/SystemVPNConnectionController.swift` | Public `SCNetworkConnection` callback-backed start/stop |
| `UI/VPNStatusView.swift` | The popup row and its power glyph |
| `Settings/SettingsStore.swift` | Default selection and the migration marker |

## Verifying by hand

```bash
# Tunnels, with the flags and addresses the classifier sees
for i in $(ifconfig -l | tr ' ' '\n' | grep -E '^(utun|ppp|ipsec|tap|tun)'); do
  echo "--- $i"; ifconfig "$i" | grep -E 'flags|inet '
done

# Configured VPN services and their state
scutil --nc list

# The proxy dictionary the row reads
scutil --proxy
```

## Tests

| File | Covers |
| --- | --- |
| `VPNStatusTests.swift` | Resolver output, name prefixes, the up-plus-address rule, proxy dictionary parsing |
| `VPNMonitorTests.swift` | Lifecycle, subscription, `stop()` finishing the stream, `start()` idempotence |
| `VPNRowSettingsTests.swift` | Default selection, the one-shot migration and its write-back, a switched-off row staying off |
| `VPNPowerTests.swift` | Service identity and order, proxy/tunnel-only hiding, target selection, duplicate requests, failure and refresh |
| `StatusPresentationTests.swift` | Row title and detail for a named tunnel, a bare tunnel, a proxy, both, and a PAC configuration |
| `PanelPresentationMapperTests.swift` | VPN power presentation on/off, changing, disabled and failure copy |
| `LocalizationParityTests.swift` | All twelve languages carrying the VPN keys |
