# Hammer APN script test — status as of Aug 22 2026, ~00:45

## What's confirmed working
- `change-apn-auto.sh` (current version, pulled via `wget` from
  `admin/change-apn-auto.sh` in the `mushr00msauce.github.io` repo) correctly
  identifies **eth1** as a USB730L running in **IP Passthrough mode**:
  - Dynamic gateway `30.11.88.52` (found via per-table route lookup, not the
    old broken main-table-only check)
  - Requires `Host: my.usb` header or it 307-redirect-loops forever
  - Field: `NetworksFourGLTEAPN`, current value on Hammer: `VZWINTERNET`
    (i.e. no actual change needed on this box — this was a dry run)
- Script requires `sudo` (policy routing + reading non-main routing tables).

## Bug found + worked around tonight (NOT yet fixed in the script itself)
**Stale temp files across sudo/non-sudo runs cause silent failures.**
- `/tmp/apn_probe_<iface>.html` and `/tmp/apn_cookies_<iface>.txt` get
  created once, then if a later run has a different UID context (e.g. first
  run without sudo, later run with sudo), writes to those same files fail
  with "Permission denied" — silently, because the script suppresses stderr
  with `2>/dev/null`. Net effect: probe looks like it got zero bytes back,
  detection reports `unknown`, script looks hung/broken even though the
  network path is fine.
- Root cause is kernel `fs.protected_regular` hardening (root can't blindly
  overwrite a non-root-owned file in a sticky dir like /tmp).
- **Workaround used tonight:** manually `sudo rm -f` all the temp files
  before each real test run.
- **Permanent fix still needed:** script should `rm -f` its own temp files
  at the very start of each run (or use a fresh per-run tmp path, e.g.
  `mktemp`), so this can never bite silently again on any box.

## Also found + worked around: leftover ip rule/route state between manual
tests. Manual debugging commands during troubleshooting add `ip rule`/`ip
route` entries in tables 200+idx — if a Ctrl+C interrupts a script run or a
manual test before its own cleanup lines run, that state lingers and can
collide with the next attempt (this happened on both eth1 table 201 and
eth2 table 202 tonight). Always double check with `sudo ip rule show` /
`sudo ip route show table <N>` before assuming a hang is a "new" bug.

## UNRESOLVED — eth2 on Hammer
- USB730L (per `dmesg`: idVendor=1410, idProduct=9032, "MiFi USB730L",
  registers via `rndis_host` driver — different from eth1's `cdc_ether`).
- Interface IP `100.112.159.244/29`, real gateway `100.112.159.245`
  (confirmed via `ip route show table all`, not a fallback).
- Direct `wget` to `http://100.112.159.245/networks/` (no header, plain —
  the "standard mode" 730L pattern) gives a **genuine connection timeout**,
  reproduced cleanly with zero leftover routing/file state in play. Not a
  redirect loop, not a permissions issue — the port just isn't answering.
- belaUI shows eth2 as connected and passing traffic fine, so the modem
  itself is working — this looks like it may not expose an HTTP admin page
  on this gateway/port at all, or needs a completely different vhost/header
  we haven't tried yet.
- dmesg shows a `ttyACM0` USB ACM device registered alongside eth1's modem —
  worth checking whether eth2's modem has an equivalent serial device, since
  an much earlier (unrelated box) session found that some of these dongles
  need AT commands over USB serial instead of an HTTP admin page.

## Next session — start here
1. `dmesg | grep -i ttyACM` and `ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null`
   on Hammer, to see if eth2's modem exposes a serial console.
2. If yes: look into AT command approach for reading/setting APN via serial
   instead of HTTP (this may need `screen`/`minicom`/`atinout` — check
   what's installed).
3. If no serial device: try other likely vhosts against
   `100.112.159.245:80` (`my.usb` didn't error out here specifically since
   we never tried it on eth2 — only tested on eth1 tonight) or try port 443.
4. Once eth2's pattern is understood, add it as a 4th combo in
   `change-apn-auto.sh`'s fingerprint loop, same pattern as the other three.
5. Separately: ship the temp-file `rm -f` fix described above — this is a
   real bug regardless of what eth2 turns out to need.

## Files involved (all in `mushr00msauce.github.io` repo, `admin/` folder)
- `change-apn-auto.sh` — current version has combos 1–3 (usb800, 730L
  passthrough, 730L standard). Confirmed working for combo 2 (passthrough)
  tonight on eth1.
- `change-apn.sh` — manual single-modem version, untouched.
- `apn-remote-guide.html` — runbook, currently at v5, matches the script
  above. Will need a v6 note once eth2's pattern + the temp-file fix land.
