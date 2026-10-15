# ntfsremount

A tiny macOS background service that makes NTFS drives **writeable in Finder** — so you can drag-and-drop files onto a Windows-formatted USB stick without reaching for a terminal.

## The problem

macOS ships an NTFS driver that is **read-only**. When you plug in an NTFS drive it mounts fine, you can copy files *off* it, but the moment you try to drag a file *onto* it Finder silently refuses — or you get "the volume cannot be modified".

A truly native, read-write NTFS driver would require an Apple-granted entitlement (the new FSKit module route), which is only available to vetted vendors. `ntfsremount` takes the practical path instead:

> It watches for NTFS volumes, and the instant macOS mounts one read-only, it remounts it **read-write** using [`ntfs-3g`](https://github.com/tuxera/ntfs-3g) on top of [FUSE-T](https://github.com/macos-fuse-t/fuse-t) (a kext-less FUSE implementation that works on current macOS). From that point on the drive behaves like any other disk.

## How it works

A root LaunchDaemon polls the mount table (`getfsstat`) every 1.5s. When it sees a `ntfs` filesystem mounted under `/Volumes/…` it:

1. unmounts the read-only mount,
2. remounts the device read-write with `ntfs-3g`, using `allow_other` and the console user's `uid`/`gid` so the volume is owned by *you*, not by root,
3. if the read-write mount fails for any reason, **restores the original read-only mount** so you are never worse off.

It only touches NTFS volumes under `/Volumes`, and it keeps a per-device cool-down so a failing mount can't thrash.

## Requirements

- macOS (developed and tested on **macOS 27**)
- [FUSE-T](https://github.com/macos-fuse-t/fuse-t) — install with `brew install --cask fuse-t`
- An `ntfs-3g` build **linked against FUSE-T**. The stock Homebrew `ntfs-3g` links against macFUSE and will not work here. Use the included `scripts/build-ntfs3g.sh`, which builds `ntfs-3g` 2022.10.3 against FUSE-T into `/opt/homebrew/opt/ntfs-3g-t`.
- Xcode Command Line Tools (for `swiftc` and `clang`)
- `autoconf`, `automake`, `libtool`, `pkg-config` (to build ntfs-3g from source)

```sh
brew install --cask fuse-t
brew install autoconf automake libtool pkg-config
./scripts/build-ntfs3g.sh
```

## Install

```sh
make install      # asks for your password; installs and starts the LaunchDaemon
make status       # confirm it is loaded
```

## Usage

Plug in an NTFS drive. Within a second or two the read-only mount is swapped for the writeable one and the volume appears under `/Volumes/<label>`. Drag-and-drop now works like a normal disk. No commands to run.

## Verify

With a drive plugged in:

```sh
mount | grep -i ntfs      # after a successful remount there should be NO "ntfs" line
tail -f /var/log/ntfsremount.log   # watch it react to plug-in / unplug events
```

## Uninstall

```sh
make uninstall
```

## Configuration

The `ntfs-3g` path is a constant near the top of `Sources/ntfsremount/main.swift`:

```swift
private let ntfs3gPath = "/opt/homebrew/opt/ntfs-3g-t/bin/ntfs-3g"
```

Change it if you installed the FUSE-T build somewhere else, then `make clean && make install`.

## Limitations

- **Speed.** Going through FUSE-T has overhead; throughput is well below the raw USB speed. Fine for documents and media files, not ideal for giant sustained transfers.
- It remounts **every** NTFS volume under `/Volumes`, with no per-device allow-list.
- Some sandboxed apps may need "Network Volumes" permission (FUSE-T presents the mount over NFS internally).
- Ejecting from Finder may need a moment to fully release the device.

## License

MIT — see [LICENSE](LICENSE).
