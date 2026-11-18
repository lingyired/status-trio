# Audio device priority

In **Settings → Audio**, enable **Switch automatically by priority** separately
for output devices and microphones. Both switches default to off. The matching
audio module must be enabled; turning that module off pauses automatic switching
without clearing its saved preference.

Drag devices to choose their priority. The same order controls the status-panel
list. The first connected, available device with a stable CoreAudio UID wins.
Unchecking a device hides it and excludes it from automatic selection. Display
limits do not limit the candidates, and a hidden device selected manually still
appears as the current device in the status panel.

Disconnected devices retain their names and positions in Settings. They can be
reordered or forgotten there. Forgetting removes their saved order, name and
hidden preference. A later connection discovers the device again at the end.
Devices without a stable UID remain available for manual selection only.

For input, priority wins regardless of connection order. If macOS changes the
default microphone after a lower-priority device connects, Status Trio restores
the highest-priority available microphone, including delayed default-device
notifications. Only selecting a microphone in Status Trio's panel creates a
manual override. CoreAudio does not identify who changed the default, so manual
input changes in macOS Settings or other apps are also corrected by this rule.
Output retains its independent switch and accepts external manual selections;
leave output automation off to let macOS manage playback.

Manual overrides temporarily take precedence. They last
until the connected device set changes in that direction, its order or hidden
preferences change, or automatic switching is enabled again. Another direction's
changes, duplicate callbacks, volume adjustments and device renames do not reset
the override. Application restart reapplies priorities; waking refreshes devices
and only a changed device set resets the override.

Automatic switching works with the windows and status panel closed. It reuses
CoreAudio device notifications and inventory caches without adding a periodic
poll, Bluetooth scan or microphone process-usage timer. System-default output
and sound-effects output follow the existing output selection behavior. Programs
that explicitly route audio to a particular device may ignore system defaults.

No eligible candidate leaves the current system route alone. A failed or timed
out switch displays an error in Audio settings and waits for the next device or
rule change. Queued automatic writes are cancelled when superseded, and verify
the UID before writing; a synchronous HAL call already running cannot be undone.

The design was inspired by [AudioPriorityBar](https://github.com/tobi/AudioPriorityBar).
This implementation uses Status Trio's existing CoreAudio controls and keeps one
output list, without speaker/headphone modes.

## 简体中文

在“设置 → 声音”的输出设备和输入设备区域分别开启“按优先级自动切换”。
两个开关默认关闭；对应声音模块关闭时暂停自动切换，并保留开关偏好。

拖动设备调整优先级，列表越靠前越优先。取消设备勾选会同时隐藏设备并将其排除
出自动切换候选。已断开的设备保留名称和排序，可以继续拖动，或通过垃圾桶按钮
忘记；再次连接时会作为新设备追加到列表末尾。面板显示数量限制不影响自动选择。

输入设备不受连接先后顺序影响。例如 A 的优先级高于 B 时，先连接 A、再连接 B，
仍使用 A；即使 macOS 延迟将默认输入改成 B，程序也会切回 A。只有在 Status Trio
面板中手动选择输入设备才会临时覆盖规则。CoreAudio 不提供切换来源，因此在系统
设置或其他应用中更改默认输入也会被优先级规则纠正。输出仍由独立开关控制；关闭
输出自动切换即可继续由 macOS 管理播放设备。

面板中的手动选择会临时覆盖自动规则，直到该方向的设备连接集合、排序或隐藏规则变化，
或重新启用自动切换。关闭窗口后仍可自动切换。应用重启会重新应用优先级；唤醒
会刷新设备，仅实际连接集合变化才解除手动覆盖。切换失败时显示提示，等待下一次
设备或规则变化，不反复重试。使用应用内固定音频设备的程序可能不跟随系统默认值。
