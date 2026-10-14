# RZG2L Remote Debugging over USB serial (VS Code + gdbserver)

Debug the aarch64 `hello` app on the RZG2L board from VS Code on Windows **without Ethernet**. The cross `gdb` on the PC talks to `gdbserver` on the board over the board's micro-USB cable, which appears as a serial port.

```
 VS Code (cppdbg) ──> aarch64-none-linux-gnu-gdb.exe ──<usb-port> (USB serial)──> gdbserver on /dev/ttyGS0 ──> hello-debug
                                                      <console-port> (UART console) ──> used only to start gdbserver
```

> **COM port names.** `<console-port>` and `<usb-port>` stand for the COM ports Windows assigned on your PC. `COM12` and `COM14` are only the examples from the PC used while setting this up; yours will differ (see [usb_readme.md](usb_readme.md), section 1).

Hardware, COM ports and the helper scripts are explained in [usb_readme.md](usb_readme.md).

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [gdbserver on the board](#2-gdbserver-on-the-board)
3. [Configure VS Code](#3-configure-vs-code)
4. [Start a debug session](#4-start-a-debug-session)
5. [Debug without VS Code (terminal)](#5-debug-without-vs-code-terminal)
6. [Troubleshooting](#6-troubleshooting)
7. [Things hardcoded to your PC](#7-things-hardcoded-to-your-pc)

## 1. Prerequisites

Everything in [usb_readme.md](usb_readme.md) works first: the UART console on `<console-port>`, the USB cable connected, and `USB: Deploy & run hello on board` succeeding.

Additionally for debugging:

| Item | Why |
|---|---|
| VS Code extension **C/C++** (`ms-vscode.cpptools`) | Provides the `cppdbg` debug type |
| Cross `gdb` on the PC | Included in the Arm GNU Toolchain: `C:\toolchains\bin\aarch64-none-linux-gnu-gdb.exe` (GDB 15.2.90) |
| **Renesas Tracing and Profiling Tools** extension disabled for this workspace | Otherwise every debug session fails with `renesas/get_cores` (see [section 3.3](#33-disable-the-renesas-tracing-and-profiling-extension-for-this-workspace)) |
| **WSL** (any Ubuntu) with `make`, `gcc`, `g++`, `curl`, `xz`, `tar` | Only needed once, to build `gdbserver` if the board doesn't have it yet. No `sudo` needed |
| No terminal program holding `<console-port>` or `<usb-port>` | A COM port can be opened by only one program |

The minimal Yocto image on the board has **no `gdb`, no `gdbserver` and no `opkg`**, so `gdbserver` has to be built on the PC and copied over.

## 2. gdbserver on the board

The board needs a static aarch64 `gdbserver` at `/home/root/apps/gdbserver`. Check whether it is already there:

```bash
export MSYS_NO_PATHCONV=1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/console.ps1 -Cmd '/home/root/apps/gdbserver --version | head -1'
```

Expected: `GNU gdbserver (GDB) 15.2`. If so, skip to [section 3](#3-configure-vs-code). If it is missing, build it once (2.1) and send it to the board (2.2).

### 2.1 Build gdbserver (once, in WSL)

Build a **static** aarch64 `gdbserver` from the GDB 15.2 source. The version matches the cross `gdb` on the PC (15.2.90), which avoids protocol mismatches. Static linking avoids glibc differences with the board's older Yocto image.

**Why WSL:** building natively in Git Bash works in principle, but autotools spawns hundreds of small test programs and Windows process creation makes it take well over an hour. In WSL it takes a few minutes.

**Toolchain in WSL vs Windows:** the build needs a Linux-hosted aarch64 cross-compiler inside WSL. The Windows one in `C:\toolchains` is a Windows `.exe` build and cannot run there. Both are Arm GNU Toolchain 14.3.Rel1 targeting `aarch64-none-linux-gnu`, so they produce the same kind of binaries, but they are separate downloads:

| | Windows (hello app) | WSL (`gdbserver`) |
|---|---|---|
| Package | `arm-gnu-toolchain-14.3.rel1-mingw-w64-i686-aarch64-none-linux-gnu` | `arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-linux-gnu` |
| Runs on | Windows (`.exe`) | Linux (ELF) |
| Location | `C:\toolchains` | `~/gdbserver-build` in WSL |

The WSL copy is only used for this one-time `gdbserver` build. The script below downloads it in step 1, so there is nothing else to install for it.

**Prerequisites in WSL (once):** the script needs a native compiler, `make`, `curl`, `xz` and `file`. Install them if missing (needs `sudo`):

```bash
sudo apt update
sudo apt install -y build-essential curl xz-utils file
```

Run the following **inside WSL** (open an Ubuntu terminal, or prefix commands with `wsl -d Ubuntu-24.04 --`). No `sudo` is needed for the build itself.

```bash
set -e
WORK="$HOME/gdbserver-build"
TC_VER="14.3.rel1"
TC_NAME="arm-gnu-toolchain-${TC_VER}-x86_64-aarch64-none-linux-gnu"
GDB_VER="15.2"
mkdir -p "$WORK" && cd "$WORK"

# 1. Linux-hosted Arm cross-compiler (same version as the Windows one)
curl -L --fail -o "$TC_NAME.tar.xz" \
  "https://developer.arm.com/-/media/Files/downloads/gnu/${TC_VER}/binrel/${TC_NAME}.tar.xz"
tar -xf "$TC_NAME.tar.xz"
export PATH="$WORK/$TC_NAME/bin:$PATH"

# 2. GDB source
curl -L --fail -O "https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VER}.tar.xz"
tar -xf "gdb-${GDB_VER}.tar.xz"

# 3. Configure and build gdbserver only, statically linked
mkdir -p build && cd build
LDFLAGS="-static" ../gdb-${GDB_VER}/configure \
  --host=aarch64-none-linux-gnu \
  --target=aarch64-none-linux-gnu \
  --disable-gdb --disable-binutils --disable-ld --disable-gas --disable-gprof \
  --disable-sim --disable-gdbtk --disable-nls --disable-werror \
  --disable-inprocess-agent --enable-gdbserver
make -j"$(nproc)" all-gdbserver

# 4. Strip and copy to Windows
aarch64-none-linux-gnu-strip -o /mnt/c/toolchains/gdbserver-aarch64 gdbserver/gdbserver
```

Notes:

- Linker warnings like `Using 'getpwnam_r' in statically linked applications...` are harmless; `gdbserver` doesn't use those functions.
- Result: a stripped, static aarch64 ELF of about 1.5 MB at `C:\toolchains\gdbserver-aarch64`.
- Check it: `file gdbserver/gdbserver` should say `ELF 64-bit LSB executable, ARM aarch64 ... statically linked`.
- If you start the build from Git Bash with `wsl ... bash /mnt/c/...`, set `MSYS_NO_PATHCONV=1`, or Git Bash rewrites the path. Background jobs started with `&` inside a single `wsl` call are killed when the call returns.

### 2.2 Send gdbserver to the board over USB

```bash
export MSYS_NO_PATHCONV=1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/usb-init.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/usb-deploy.ps1 -Src C:/toolchains/gdbserver-aarch64 -Name gdbserver
```

Then run the version check above again. This is a one-time step; the VS Code tasks only redeploy the app, not `gdbserver`.

## 3. Configure VS Code

### 3.1 Tasks: [.vscode/tasks.json](.vscode/tasks.json)

| Task | What it does |
|---|---|
| `Build hello-debug (GCC, aarch64)` | `-static -g -O0` into `hello-debug` |
| `USB: Init board link` | Loads `g_serial`, prepares `/dev/ttyGS0`, installs `recv.py` if missing, stops old `gdbserver` |
| `USB: Deploy hello-debug to board` | Build, init, then sends `hello-debug` over `<usb-port>` |
| `USB: Start gdbserver on board` | Deploys first, then starts `gdbserver` on the board (see below) |

Task chain: `Build hello-debug` -> `USB: Init board link` -> `USB: Deploy hello-debug to board` -> `USB: Start gdbserver on board`.

The start command typed on the board console is:

```bash
setsid /home/root/apps/gdbserver /dev/ttyGS0 /home/root/apps/hello-debug < /dev/null > /dev/console 2>&1 &
```

- `gdbserver /dev/ttyGS0 <program>` makes `gdbserver` talk over the USB serial port instead of a TCP port.
- `setsid` plus the redirections detach it from the login shell. Without them the console shell **logs itself out** as soon as `gdbserver` starts.
- The program's own output goes to `/dev/console`, so it appears in a terminal program on `<console-port>` (not in VS Code).
- This task is not a background task: it ends once `gdbserver` is started, and `gdbserver` keeps waiting on the board for gdb.

### 3.2 Launch config: [.vscode/launch.json](.vscode/launch.json)

The file in this workspace uses the example port `COM14`. Replace it with your `<usb-port>`.

```json
{
    "name": "Debug hello on RZG2L (USB serial COM14)",
    "type": "cppdbg",
    "request": "launch",
    "program": "${workspaceFolder}/hello-debug",
    "cwd": "${workspaceFolder}",
    "stopAtEntry": true,
    "MIMode": "gdb",
    "miDebuggerPath": "C:/toolchains/bin/aarch64-none-linux-gnu-gdb.exe",
    "miDebuggerServerAddress": "\\\\.\\COM14",
    "preLaunchTask": "USB: Start gdbserver on board",
    "setupCommands": [
        { "text": "set serial baud 115200", "ignoreFailures": false },
        { "text": "set remotetimeout 20", "ignoreFailures": true },
        { "text": "-enable-pretty-printing", "ignoreFailures": true }
    ]
}
```

- `miDebuggerServerAddress` is the USB serial port (`<usb-port>`; `COM14` in the example). It is written as `\\.\COM14` (JSON-escaped above); this form works for every COM number, including those above `COM9`.
- `set serial baud 115200` is required by gdb for serial targets. The real speed is the USB speed, not 115200.
- `set remotetimeout 20` gives slow replies more time.
- `program` is the local `hello-debug` (with symbols). It must be the same build as the one on the board; the task chain guarantees this.

### 3.3 Disable the Renesas Tracing and Profiling extension for this workspace

If the **Renesas Tracing and Profiling Tools** extension (`renesas-rpm`) is enabled, every debug session (even a plain `cppdbg` one) fails immediately with:

```
Stopping due to fatal error: InvalidOperationException: No handler registered for request of type 'renesas/get_cores'!
```

That extension sends a Renesas-only request (`renesas/get_cores`) to all debug sessions, and the Microsoft C/C++ debug adapter doesn't understand it.

When this happens the breakpoints are bound correctly (the Debug Console shows `AD7BreakpointBoundEvent`), but the session is killed before gdb continues, so the program never stops at `main`.

Fix:

1. Open the Extensions view (`Ctrl+Shift+X`) and search for `@id:renesaselectronicscorporation.renesas-rpm`. A plain text search or scrolling the list is easy to get wrong: the installed list is alphabetical, and this extension sits below **Renesas Smart Manual**.
2. Click the gear icon, then **Disable (Workspace)**.
3. Click the blue **Restart Extensions** button on the extension page, or run **Developer: Reload Window**. The extension host must actually restart; disabling alone isn't enough, and the extension shows **Restart Required** until you do.
4. Check that the extension page now says it is disabled in this workspace and offers **Enable (Workspace)**.

Other Renesas extensions don't depend on it, and other workspaces keep it enabled. If the workspace-level disable is ignored, use plain **Disable** (all workspaces), reload, and re-enable it later when you need it.

## 4. Start a debug session

1. Plug in the UART adapter and the micro-USB cable. Make sure no terminal program holds `<console-port>`/`<usb-port>`.
2. Open [hello.c](hello.c) and set a breakpoint in the gutter.
3. In **Run and Debug** (`Ctrl+Shift+D`) pick the USB serial debug entry (named `Debug hello on RZG2L (USB serial COM14)` in the example) and press `F5`.
4. VS Code builds, initialises the link, copies `hello-debug`, starts `gdbserver` and attaches. It stops at the beginning of `main`.
5. Use Continue `F5`, Step Over `F10`, Step Into `F11`, and the Variables, Watch and Call Stack panes.

The output `Hello, World from RZG2L!` is printed on the board console (`<console-port>`). To see it, open a terminal program on `<console-port>` after the session, or run `scripts/console.ps1 -Cmd 'true'` while the program runs.

Tested result (command-line sequence, not through the VS Code F5 UI): breakpoint at `main` hit, backtrace `#0 main () at hello.c:5`, program ran to `exited normally`.

## 5. Debug without VS Code (terminal)

Useful to isolate problems.

```bash
export MSYS_NO_PATHCONV=1
export PATH=/c/toolchains/bin:$PATH

# 1. build, prepare the link, send the binary
source /c/toolchains/env.sh
aarch64-none-linux-gnu-gcc -static -g -O0 -o hello-debug hello.c
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/usb-init.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/usb-deploy.ps1 -Src hello-debug

# 2. start gdbserver on the board (through the console)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/console.ps1 -WaitMs 4000 -IdleMs 1500 \
  -Cmd 'setsid /home/root/apps/gdbserver /dev/ttyGS0 /home/root/apps/hello-debug < /dev/null > /dev/console 2>&1 &'

# 3. attach (scripted smoke test), or run the same commands by hand
aarch64-none-linux-gnu-gdb -batch -x scripts/test-usb.gdb
```

[scripts/test-usb.gdb](scripts/test-usb.gdb) contains:

```
set serial baud 115200
set remotetimeout 20
file hello-debug
target remote \\.\COM14
break main
continue
bt
continue
```

(`COM14` is the example; use your `<usb-port>`.)

For an interactive session replace `-batch -x ...` with `-tui -ex "set serial baud 115200" -ex "target remote \\\\.\\COM14" hello-debug` (note the extra backslash escaping in a shell).

## 6. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Access to the port ... is denied` | Another program holds `<console-port>` or `<usb-port>` (terminal program, an earlier gdb or a stuck debug session). Stop the debug session or close the program; if needed, reload the window to end a leftover `OpenDebugAD7.exe`. |
| `Ignoring packet error, continuing...` / `Remote communication error` / timeout on attach | `gdbserver` isn't running or isn't on `/dev/ttyGS0`. Run `USB: Init board link`, then `USB: Start gdbserver on board`. Check that `ps` on the board shows `gdbserver /dev/ttyGS0 ...` |
| Debugger can't open `<usb-port>` / `No such file` | The COM number changed (different USB port), or the port is gone because the board was rebooted and `g_serial` isn't loaded. In the second case run `modprobe g_serial` on the board console (or the `USB: Init board link` task) and check `cat /sys/class/udc/11c60000.usb/state` prints `configured`. Otherwise check Device Manager and update [.vscode/launch.json](.vscode/launch.json) and [scripts/test-usb.gdb](scripts/test-usb.gdb) |
| Console shows `login:` / `Password:` after starting `gdbserver` | `gdbserver` was started directly from the console shell and logged it out. Use the `setsid ... &` form above, then log in again (`Ctrl+C`, type `root`) |
| Several `gdbserver` processes on the board | Old ones from earlier sessions. `USB: Init board link` stops them |
| `No handler registered for request of type 'renesas/get_cores'` | Disable the **Renesas Tracing and Profiling Tools** extension for the workspace and **restart the extensions / reload the window** (section 3.3) |
| Debug session stays "running", never stops at `main`, no Call Stack | Either the Renesas extension error above killed the session (check the Debug Console), or the program already finished on the board. Stop the session, rerun with `F5` |
| Need more detail about a failing session | Add `"logging": { "engineLogging": true }` to the launch entry and read the **Debug Console** (`Ctrl+Shift+Y`). Search for `break-insert`, `target-select`, `exec-continue`, `error` |
| Breakpoints don't bind / source not found | The `hello-debug` on the board differs from the local one. Re-run the deploy task; don't debug the `-O2` `hello` |
| `USB gadget not connected: plug the micro-USB cable into the PC` | The board UDC isn't `configured`. Check the micro-USB cable, then run `USB: Init board link` |
| gdb warning `could not convert 'main' from the host encoding (CP1252) to UTF-32` | Harmless |
| Tasks fail with odd path errors | A plain `bash.exe` resolved to the WSL launcher. Keep the full Git bash path in `tasks.json` ([usb_readme.md](usb_readme.md), section 3.3) |
| `wsl ... bash /mnt/c/...` fails with a mangled `C:/Users/.../Git/mnt/c/...` path | Git Bash rewrites Unix-style paths. Prefix with `MSYS_NO_PATHCONV=1` |
| clangd: `'stdio.h' file not found` | See [usb_readme.md](usb_readme.md), section 3.4 |
| `Unable to load schema from ... launch.schema.json: 404` | VS Code editor warning about its built-in schema URL; harmless |
| Building `gdbserver` in Git Bash hangs or fails with `no usable dependency style found` | Don't build natively on Windows; use WSL (section 2.1) |

## 7. Things hardcoded to your PC

| Value | Where |
|---|---|
| USB data port (`<usb-port>`, e.g. `COM14`) | [.vscode/launch.json](.vscode/launch.json) (`miDebuggerServerAddress`), [scripts/test-usb.gdb](scripts/test-usb.gdb), default in [scripts/usb-send.ps1](scripts/usb-send.ps1) and [scripts/usb-deploy.ps1](scripts/usb-deploy.ps1) |
| Console port (`<console-port>`, e.g. `COM12`) | Defaults in [scripts/console.ps1](scripts/console.ps1), [scripts/usb-init.ps1](scripts/usb-init.ps1), [scripts/usb-deploy.ps1](scripts/usb-deploy.ps1), [scripts/put-console.ps1](scripts/put-console.ps1) |
| `gdbserver` on the board `/home/root/apps/gdbserver` | [.vscode/tasks.json](.vscode/tasks.json) (`USB: Start gdbserver on board`) |
| Git bash path, toolchain root `C:\toolchains` | [.vscode/tasks.json](.vscode/tasks.json), [.vscode/launch.json](.vscode/launch.json) |
