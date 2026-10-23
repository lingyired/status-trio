#!/usr/bin/env python3
"""Remove Status Trio development entries from the Location Services client list.

Every worktree build derives its own bundle identifier
(com.lingsmbp.StatusTrio.dev.<branch>, see scripts/build-worktree.sh), and every
launch registers that identifier in /var/db/locationd/clients.plist. Deleting a
build directory never removes its entry, so System Settings > Privacy & Security
> Location Services slowly fills up with apps that no longer exist.

This script edits only that registration list. It does not touch location
authorization state, TCC, or any app bundle, and it never deletes an entry that
does not belong to Status Trio.

Usage:
    scripts/cleanup-location-services-clients.py            # report only
    sudo scripts/cleanup-location-services-clients.py --apply
    sudo scripts/cleanup-location-services-clients.py --apply --all

Default scope is "stale": entries whose recorded path no longer exists on disk.
--all additionally removes entries whose bundle is still on disk, which is only
worth doing if you are done with those builds; anything still installed and
launched will register itself again.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import time

DEFAULT_PLIST = "/var/db/locationd/clients.plist"
BUNDLE_ID_PREFIX = "com.lingsmbp.StatusTrio"
EXECUTABLE_SUFFIX = "/StatusTrio"
LOCATIOND_JOB = "system/com.apple.locationd"
LAUNCHD_PLIST = "/System/Library/LaunchDaemons/com.apple.locationd.plist"

STALE = "stale"
LIVE = "live"
UNKNOWN = "unknown"


def is_status_trio(entry):
    """True for entries registered by any Status Trio build, release or dev."""
    bundle_id = entry.get("BundleId")
    if isinstance(bundle_id, str) and bundle_id.startswith(BUNDLE_ID_PREFIX):
        return True
    if bundle_id is None:
        executable = entry.get("Executable")
        if isinstance(executable, str) and executable.endswith(EXECUTABLE_SUFFIX):
            return True
    return False


def recorded_path(entry):
    """The bundle path locationd recorded, falling back to the executable."""
    for key in ("BundlePath", "Executable"):
        value = entry.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def is_client(entry):
    return isinstance(entry, dict) and any(
        key in entry for key in ("BundleId", "BundlePath", "Executable")
    )


def classify(entries):
    """Split entries into Status Trio clients and everything else."""
    status_trio = {}
    others = {}
    for key, value in entries.items():
        if not is_client(value) or not is_status_trio(value):
            others[key] = value
            continue
        path = recorded_path(value)
        if path is None:
            state = UNKNOWN
        elif os.path.lexists(path):
            state = LIVE
        else:
            state = STALE
        status_trio[key] = (state, path)
    return status_trio, others


def running_paths():
    """Paths of running processes, so the report can flag live bundles."""
    try:
        completed = subprocess.run(
            ["/bin/ps", "-axo", "comm="],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return set()
    return {line.strip() for line in completed.stdout.splitlines() if line.strip()}


def label(entry):
    bundle_id = entry.get("BundleId")
    return bundle_id if isinstance(bundle_id, str) and bundle_id else "(no bundle id)"


def print_report(entries, status_trio, scope, running):
    print("Location Services client list: {}".format(DEFAULT_PLIST))
    print(
        "  {} entries total, {} registered by Status Trio, {} untouched".format(
            len(entries), len(status_trio), len(entries) - len(status_trio)
        )
    )
    print()

    if not status_trio:
        print("Nothing to do: no Status Trio entries are registered.")
        return

    rows = []
    for key, (state, path) in status_trio.items():
        active = path is not None and path in running
        rows.append((state, label(entries[key]), path or "(no recorded path)", active))
    rows.sort(key=lambda row: (row[0] != STALE, row[1]))

    id_width = max(len(row[1]) for row in rows)
    state_width = max(len(row[0]) for row in rows)
    print(
        "  {:<{sw}}  {:<{iw}}  {}".format(
            "STATE", "BUNDLE ID", "RECORDED PATH", sw=state_width, iw=id_width
        )
    )
    for state, bundle_id, path, active in rows:
        suffix = "  [running]" if active else ""
        print(
            "  {:<{sw}}  {:<{iw}}  {}{}".format(
                state, bundle_id, path, suffix, sw=state_width, iw=id_width
            )
        )
    print()

    stale = [row for row in rows if row[0] == STALE]
    live = [row for row in rows if row[0] == LIVE]
    unknown = [row for row in rows if row[0] == UNKNOWN]
    print(
        "  {} stale (path gone), {} live (still on disk), {} unknown".format(
            len(stale), len(live), len(unknown)
        )
    )
    if unknown:
        print("  Unknown entries have no recorded path and are never removed.")
    print()
    print("  Scope: {}".format(scope))


def select(status_trio, scope):
    if scope == STALE:
        return sorted(key for key, (state, _) in status_trio.items() if state == STALE)
    return sorted(
        key for key, (state, _) in status_trio.items() if state != UNKNOWN
    )


def locationd_pid():
    probe = subprocess.run(
        ["/usr/bin/pgrep", "-x", "locationd"],
        capture_output=True,
        text=True,
        check=False,
    )
    if probe.returncode != 0 or not probe.stdout.split():
        return None
    return probe.stdout.split()[0]


def wait_for_locationd(want_running, timeout=10.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pid = locationd_pid()
        if (pid is not None) == want_running:
            return pid
        time.sleep(0.25)
    return locationd_pid()


def stop_locationd():
    """Take locationd down before the file is edited.

    A plain SIGTERM is not enough: launchd restarts the daemon immediately, and
    locationd writes its cached registrations back out while shutting down, so
    killing it after the edit can undo the edit. bootout keeps the job down and
    lets that shutdown flush land first.
    """
    print("Stopping locationd...")
    subprocess.run(
        ["/usr/bin/launchctl", "bootout", LOCATIOND_JOB],
        capture_output=True,
        text=True,
        check=False,
    )
    if wait_for_locationd(False) is None:
        print("  locationd is down.")
        return True
    print("  bootout did not stop it; sending SIGTERM.")
    subprocess.run(
        ["/usr/bin/launchctl", "kill", "SIGTERM", LOCATIOND_JOB],
        capture_output=True,
        text=True,
        check=False,
    )
    if wait_for_locationd(False, timeout=5.0) is None:
        print("  locationd is down.")
        return True
    print("  warning: locationd is still running; editing anyway.")
    return False


def start_locationd():
    print("Starting locationd...")
    completed = subprocess.run(
        ["/usr/bin/launchctl", "bootstrap", "system", LAUNCHD_PLIST],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()
        print("  launchctl bootstrap failed ({}): {}".format(completed.returncode, detail))
    pid = wait_for_locationd(True)
    if pid is not None:
        print("  locationd is running (pid {})".format(pid))
        return True
    print("  error: locationd did not come back within 10s. Recover with:")
    print("    sudo /usr/bin/launchctl bootstrap system {}".format(LAUNCHD_PLIST))
    print("    sudo /usr/bin/launchctl kickstart -k {}".format(LOCATIOND_JOB))
    print("  or reboot.")
    return False


def apply(plist_path, entries, status_trio, keys, all_scope, running):
    if os.geteuid() != 0:
        print("error: --apply must run as root; try:", file=sys.stderr)
        print("  sudo /usr/bin/python3 {}".format(os.path.abspath(__file__)), file=sys.stderr)
        return 1

    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = "{}.backup-{}".format(plist_path, stamp)
    print("Backing up to {}".format(backup))
    shutil.copy2(plist_path, backup)
    subprocess.run(["/usr/bin/plutil", "-lint", backup], capture_output=True, check=False)

    if all_scope:
        active = [
            label(entries[key])
            for key in keys
            if status_trio[key][1] is not None and status_trio[key][1] in running
        ]
        if active:
            print()
            print(
                "  note: {} of these bundles are running right now and will "
                "register themselves again:".format(len(active))
            )
            for name in active:
                print("    {}".format(name))

    updated = dict(entries)
    for key in keys:
        updated.pop(key, None)
    print("Removing {} of {} Status Trio entries".format(len(keys), len(status_trio)))
    stop_locationd()

    tmp = plist_path + ".new"
    with open(tmp, "wb") as handle:
        plistlib.dump(updated, handle, fmt=plistlib.FMT_BINARY, sort_keys=False)
    stat = os.stat(plist_path)
    os.chown(tmp, stat.st_uid, stat.st_gid)
    os.chmod(tmp, stat.st_mode & 0o777)
    os.replace(tmp, plist_path)
    print("Wrote {}".format(plist_path))

    if not start_locationd():
        return 1

    with open(plist_path, "rb") as handle:
        after = plistlib.load(handle)
    after_trio, _ = classify(after)
    survivors = [key for key in keys if key in after_trio]
    print(
        "After restart: {} Status Trio entries registered, {} of the removed "
        "ones reappeared".format(len(after_trio), len(survivors))
    )
    for key in survivors:
        print("  {} <- {}".format(label(after[key]), after[key].get("BundlePath")))
    print()
    print("Restore with:")
    print("  sudo cp {b} {p}".format(b=backup, p=plist_path))
    print("  sudo /usr/bin/launchctl kickstart -k {}".format(LOCATIOND_JOB))
    print("Close and reopen System Settings to refresh the list.")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Remove Status Trio development entries from the Location Services "
            "client list."
        )
    )
    parser.add_argument(
        "--plist",
        default=DEFAULT_PLIST,
        help="client list to edit (default: {})".format(DEFAULT_PLIST),
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="write the change and restart locationd; without it the script only reports",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="also remove entries whose bundle is still on disk (default: stale only)",
    )
    args = parser.parse_args()

    if not os.path.exists(args.plist):
        print("error: {} not found".format(args.plist), file=sys.stderr)
        return 1
    try:
        with open(args.plist, "rb") as handle:
            entries = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        print("error: cannot read {}: {}".format(args.plist, error), file=sys.stderr)
        return 1
    if not isinstance(entries, dict):
        print("error: {} is not a dictionary".format(args.plist), file=sys.stderr)
        return 1

    status_trio, _ = classify(entries)
    scope = "all" if args.all else STALE
    running = running_paths()
    print_report(entries, status_trio, scope, running)

    keys = select(status_trio, scope)
    print()
    if not keys:
        print("Nothing selected for removal.")
        return 0
    noun = "entry" if len(keys) == 1 else "entries"
    print("{} {} selected for removal.".format(len(keys), noun))
    if not args.apply:
        print("Report only. Re-run with --apply (as root) to write the change.")
        return 0
    return apply(args.plist, entries, status_trio, keys, args.all, running)


if __name__ == "__main__":
    sys.exit(main())
