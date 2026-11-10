#!/usr/bin/env bash
# Offline packaging regression: no Finder, disk image, or privileged operation.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioDMGTest.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
cleanup() { [[ "$WORK" == */StatusTrioDMGTest.* ]] && rm -rf -- "$WORK"; }
trap cleanup EXIT
fail() { echo "DMG regression failed: $*" >&2; exit 1; }
python3 - "$ROOT/assets/dmg" <<'PY'
import pathlib
import struct
import sys
for name, width, height, dpi in [("background.png", 660, 420, 72), ("background@2x.png", 1320, 840, 144)]:
    data = (pathlib.Path(sys.argv[1]) / name).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "Background must be PNG"
    assert struct.unpack(">II", data[16:24]) == (width, height), "Background pixel dimensions changed"
    offset = 8
    resolution = None
    while offset < len(data):
        size = struct.unpack(">I", data[offset:offset + 4])[0]
        if data[offset + 4:offset + 8] == b"pHYs":
            resolution = struct.unpack(">IIB", data[offset + 8:offset + 17])
        offset += size + 12
    # 72 DPI is PNG/AppKit default and may omit pHYs; Retina must be explicit.
    if dpi == 144 or resolution:
        assert resolution and resolution[2] == 1, "Background has no physical resolution"
        assert all(abs(value * .0254 - dpi) < .02 for value in resolution[:2]), "Background point dimensions changed"
PY
mkdir -p "$WORK/bin" "$WORK/Status Trio.app/Contents/Resources" "$WORK/temp"
printf 'fixture-icon' > "$WORK/Status Trio.app/Contents/Resources/AppIcon.icns"
export DMG_TRACE="$WORK/trace" DMG_INFO="$WORK/info.plist" TMPDIR="$WORK/temp"
cat > "$WORK/bin/create-dmg" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then echo "create-dmg ${MOCK_VERSION:-1.3.0}"; exit; fi
printf '%s\n' "$@" > "$DMG_TRACE"
printf '%s\n' "${TMPDIR:?}" > "$DMG_TRACE.tmpdir"
printf 'fixture temporary AppleScript' > "$TMPDIR/createdmg.fixture"
args=("$@")
output="${args[${#args[@]}-2]}"
staging="${args[${#args[@]}-1]}"
[[ -d "$staging/Status Trio.app" ]] || exit 81
[[ ! -e "$staging/Applications" && ! -L "$staging/Applications" ]] || exit 82
if [[ "${MOCK_LAYOUT_FAIL:-0}" == 1 ]]; then
    ruby -rcgi -e '
      own = File.join(File.dirname(ARGV[0]), "rw.fixture.dmg")
      File.write(own, "fixture")
      File.write(ENV.fetch("DMG_INFO"), "<?xml version=\"1.0\"?><plist><dict><key>images</key><array>" +
        [[own, ["/dev/disk991s1", "/dev/disk991"]], ["/other/rw.fixture.dmg", ["/dev/unrelated-fixture"]]].map { |path, devices|
          "<dict><key>image-path</key><string>#{CGI.escapeHTML(path)}</string><key>system-entities</key><array>" + devices.map { |dev| "<dict><key>dev-entry</key><string>#{dev}</string></dict>" }.join + "</array></dict>"
        }.join + "</array></dict></plist>")
    ' "$output"
    echo 'fixture Finder layout failed' >&2
    exit 42
fi
printf 'fixture disk image' > "$output"
MOCK
cat > "$WORK/bin/hdiutil" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == info ]]; then
    if [[ -f "$DMG_INFO" ]]; then cat "$DMG_INFO"; else printf '<plist><dict><key>images</key><array/></dict></plist>'; fi
elif [[ "$1" == detach ]]; then
    # Only the owned backing image belongs to the cleanup contract; the helper
    # re-mount uses its own mock path and must not pollute that count.
    if [[ "$2" == /dev/disk991 ]]; then
        printf 'detach %s\n' "$2" >> "$DMG_TRACE"
    else
        printf 'unmount %s\n' "$2" >> "$DMG_TRACE"
    fi
    [[ "${MOCK_DETACH_FAIL:-0}" != 1 ]] || exit 16
elif [[ "$1" == convert ]]; then
    # The installer re-opens the image to hide helper dotfiles, then repacks.
    # Mirror it as an opaque copy so the offline regression never touches a real disk.
    printf 'convert %s\n' "$*" >> "$DMG_TRACE"
    shift  # drop "convert"
    dest=""
    prev=""
    for arg in "$@"; do
        [[ "$prev" == "-o" ]] && dest="$arg"
        prev="$arg"
    done
    [[ -n "$dest" ]] || exit 85
    cp "${@: -1}" "$dest"
elif [[ "$1" == attach ]]; then
    # Emit a real, writable directory as the mount point so chflags can run.
    mnt="${DMG_MOCK_MNT:?}"
    mkdir -p "$mnt"
    : > "$mnt/.VolumeIcon.icns"
    : > "$mnt/.background"
    mkdir -p "$mnt/Status Trio.app"
    printf 'attach %s\n' "$*" >> "$DMG_TRACE"
    printf '/dev/disk992\tApple_HFS\t%s\n' "$mnt"
else
    echo "unexpected hdiutil operation: $*" >&2
    exit 84
fi
MOCK
cat > "$WORK/bin/chflags" <<'MOCK'
#!/usr/bin/env bash
printf 'hide %s\n' "$*" >> "$DMG_TRACE"
MOCK
export DMG_MOCK_MNT="$WORK/mockmnt"
chmod +x "$WORK/bin/create-dmg" "$WORK/bin/hdiutil" "$WORK/bin/chflags"
export PATH="$WORK/bin:$PATH"
SCRIPT="$ROOT/scripts/create-installer-dmg.sh"
[[ -f "$SCRIPT" ]] || fail 'installer wrapper is missing'
bash "$SCRIPT" "$WORK/Status Trio.app" "$WORK/output.dmg"
ruby -e '
  args = File.readlines(ARGV[0], chomp: true)
  required = {
    "--volname" => ["Status Trio"], "--window-size" => ["660", "420"],
    "--icon-size" => ["104"], "--text-size" => ["13"],
    "--icon" => ["Status Trio.app", "180", "230"],
    "--app-drop-link" => ["480", "230"], "--hide-extension" => ["Status Trio.app"],
    "--format" => ["UDZO"]
  }
  required.each { |flag, values| index = args.index(flag); abort "missing/wrong #{flag}" unless index && args[index + 1, values.size] == values }
  ["--background", "--no-internet-enable"].each { |flag| abort "missing #{flag}" unless args.include?(flag) }
  abort "volume icon must not be written" if args.include?("--volicon")
  abort "volume icon must not be positioned" if args.each_index.any? { |i| args[i] == "--icon" && args[i + 1] == ".VolumeIcon.icns" }
  ["--skip-jenkins", "--skip-finalize", "--sandbox-safe"].each { |flag| abort "layout bypass forbidden: #{flag}" if args.include?(flag) }
  background = args[args.index("--background") + 1]
  abort "missing Retina background" unless background.end_with?("background@2x.png") && File.file?(background)
  abort "duplicate Applications link" unless args.count("--app-drop-link") == 1
  # The hidden `.background` helper must be pinned outside the 660x420 window
  # so a Finder that shows hidden files cannot draw it over the instructions.
  index = args.each_index.find { |i| args[i] == "--icon" && args[i + 1] == ".background" }
  abort "helper .background is not positioned" unless index
  abort "helper .background overlaps the window" unless args[index + 2].to_i > 660
' "$DMG_TRACE"
[[ "$(< "$WORK/output.dmg")" == 'fixture disk image' ]] || fail 'output missing'
[[ ! -e "$(< "$DMG_TRACE.tmpdir")" ]] || fail 'successful package leaked tool temporary directory'
# The helper dotfiles create-dmg adds must be hidden so they never sit on the
# installer instructions, especially on a headless runner without Finder layout.
/usr/bin/grep -q '^hide .*\.background$' "$DMG_TRACE" \
    || fail 'background helper was not hidden'
/usr/bin/grep -q '^unmount ' "$DMG_TRACE" || fail 'helper re-mount was not detached'
# The build bundle has no space; the user-facing name must still have one.
mkdir -p "$WORK/StatusTrio.app/Contents/Resources"
printf fixture > "$WORK/StatusTrio.app/Contents/Resources/AppIcon.icns"
DMG_APP_NAME='Status Trio' bash "$SCRIPT" "$WORK/StatusTrio.app" "$WORK/display-name.dmg"
ruby -e '
  args = File.readlines(ARGV[0], chomp: true)
  {"--volname" => ["Status Trio"], "--icon" => ["Status Trio.app", "180", "230"], "--hide-extension" => ["Status Trio.app"]}.each do |flag, expected|
    index = args.index(flag)
    abort "display name ignored by #{flag}" unless index && args[index + 1, expected.size] == expected
  end
' "$DMG_TRACE"
if bash "$SCRIPT" "$WORK/Status Trio.app" "$WORK/output.dmg" > "$WORK/log" 2>&1; then fail 'overwrote an existing output'; fi
[[ "$(< "$WORK/output.dmg")" == 'fixture disk image' ]] || fail 'existing output changed'
if MOCK_VERSION=1.2.0 bash "$SCRIPT" "$WORK/Status Trio.app" "$WORK/version.dmg" > "$WORK/log" 2>&1; then fail 'accepted incompatible tool'; fi
if MOCK_LAYOUT_FAIL=1 bash "$SCRIPT" "$WORK/Status Trio.app" "$WORK/failure.dmg" > "$WORK/log" 2>&1; then fail 'layout failure succeeded'; else status=$?; fi
[[ "$status" == 42 ]] || fail "lost layout exit status: $status"
[[ ! -e "$WORK/failure.dmg" ]] || fail 'published incomplete output'
[[ "$(/usr/bin/grep -c '^detach /dev/disk991$' "$DMG_TRACE")" == 1 ]] || fail 'owned image was not detached'
[[ "$(/usr/bin/grep -c '^detach ' "$DMG_TRACE")" == 1 ]] || fail 'detached more than the whole owned disk'
[[ ! -e "$(< "$DMG_TRACE.tmpdir")/createdmg.fixture" ]] || fail 'create-dmg temporary files leaked after failure'
if /usr/bin/grep -q 'detach /dev/unrelated-fixture' "$DMG_TRACE"; then fail 'detached another image'; fi
/usr/bin/grep -q 'fixture Finder layout failed' "$WORK/log" || fail 'lost original error'
# A busy image must leave its temporary files available for manual cleanup.
if MOCK_LAYOUT_FAIL=1 MOCK_DETACH_FAIL=1 bash "$SCRIPT" "$WORK/Status Trio.app" "$WORK/busy.dmg" > "$WORK/log" 2>&1; then fail 'busy layout failure succeeded'; else status=$?; fi
[[ "$status" == 42 ]] || fail 'cleanup hid original failure'
/usr/bin/grep -q 'Preserving temporary files' "$WORK/log" || fail 'busy mount was silently discarded'
PRESERVED="$(/usr/bin/sed -n 's/^Preserving temporary files for mount cleanup: //p' "$WORK/log")"
[[ "$PRESERVED" == "$WORK"/.StatusTrioDMG.* && -d "$PRESERVED" ]] || fail 'busy image directory was not preserved'
[[ -f "$PRESERVED/rw.fixture.dmg" ]] || fail 'busy image backing file was not preserved'
[[ -f "$(< "$DMG_TRACE.tmpdir")/createdmg.fixture" ]] || fail 'busy image temporary files were not preserved'
# Retain other shell tools but make create-dmg genuinely unavailable.
mkdir "$WORK/missing-bin"
for tool in dirname pwd ruby mktemp; do ln -s "$(command -v "$tool")" "$WORK/missing-bin/$tool"; done
if PATH="$WORK/missing-bin" /bin/bash "$SCRIPT" --check > "$WORK/log" 2>&1; then fail 'missing create-dmg accepted'; fi
/usr/bin/grep -q 'create-dmg' "$WORK/log" || fail 'missing dependency diagnostic'
echo 'DMG installer offline regressions passed.'
