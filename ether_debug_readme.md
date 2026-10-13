# RZG2L Remote Debugging (VS Code + gdbserver)

Debug the aarch64 `hello` app running on the RZG2L board from VS Code on Windows. VS Code runs the cross `gdb` on the PC and talks to `gdbserver` on the board over the network.

```
 VS Code (cppdbg) ──> aarch64-none-linux-gnu-gdb.exe ──TCP :2345──> gdbserver ──> hello-debug (on board)
```

> `<board-ip>` is the board's IP address. `10.0.0.121` is only the example used while setting this up; it can be different on your network. For setup, see [ether_readme.md](ether_readme.md). Without Ethernet, see [usb_debug_readme.md](usb_debug_readme.md).

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [Build gdbserver for the board](#2-build-gdbserver-for-the-board)
3. [Deploy gdbserver to the board](#3-deploy-gdbserver-to-the-board)
4. [Configure VS Code](#4-configure-vs-code)
5. [Start a debug session](#5-start-a-debug-session)
6. [Debug without VS Code (terminal)](#6-debug-without-vs-code-terminal)
7. [Troubleshooting](#7-troubleshooting)
8. [Things hardcoded to your PC](#8-things-hardcoded-to-your-pc)

## 1. Prerequisites

Already done in [ether_readme.md](ether_readme.md) (sections 1 to 3):

- SSH/SCP to the board works (`ssh root@<board-ip>`), including the `ssh-rsa` host key workaround.
- Cross-toolchains installed under `C:\toolchains` (Arm GNU Toolchain 14.3.Rel1 and LLVM/Clang), and `source /c/toolchains/env.sh` works in Git Bash.
- `hello.c` builds into a static aarch64 binary.

Additionally for debugging:

| Item | Why |
|---|---|
| VS Code extension **C/C++** (`ms-vscode.cpptools`) | Provides the `cppdbg` debug type |
| VS Code extension **clangd** (optional) | Editor diagnostics, needs [.clangd](.clangd) (see [section 4.4](#44-clangd-editor-errors-optional)) |
| **WSL** (any Ubuntu) with `make`, `gcc`, `g++`, `curl`, `xz`, `tar` | Used once to build `gdbserver`. No `sudo` needed |
| Cross `gdb` on the PC | Already included: `C:\toolchains\bin\aarch64-none-linux-gnu-gdb.exe` (GDB 15.2.90) |

The minimal Yocto image on the board has **no `gdb`, no `gdbserver` and no `opkg`**, so `gdbserver` has to be built and copied over.

## 2. Build gdbserver for the board

Build a **static** aarch64 `gdbserver` from the GDB 15.2 source. The version matches the cross `gdb` on the PC (15.2.90), which avoids protocol mismatches. Static linking avoids glibc differences with the board's older Yocto image.

**Why WSL:** building natively in Git Bash works in principle, but autotools spawns hundreds of small test programs and Windows process creation makes it take well over an hour. In WSL it takes a few minutes.

Run these **inside WSL** (open an Ubuntu terminal, or prefix commands with `wsl -d Ubuntu-24.04 --`). No `sudo` is required.

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

## 3. Deploy gdbserver to the board

From Git Bash:

```bash
ssh root@<board-ip> 'mkdir -p /home/root/apps'
scp /c/toolchains/gdbserver-aarch64 root@<board-ip>:/home/root/apps/gdbserver
ssh root@<board-ip> 'chmod +x /home/root/apps/gdbserver && /home/root/apps/gdbserver --version | head -1'
```

Expected output: `GNU gdbserver (GDB) 15.2`.

This is a one-time step. The VS Code tasks below only redeploy the app, not `gdbserver`.

## 4. Configure VS Code

All files live in the workspace; nothing needs to be installed beyond the extensions in section 1.

### 4.1 Tasks: [.vscode/tasks.json](.vscode/tasks.json)

| Task | What it does |
|---|---|
| `Build hello (GCC, aarch64)` | Release build (`-O2`), default build task (`Ctrl+Shift+B`) |
| `Build hello (Clang, aarch64)` | Same with Clang |
| `Build hello-debug (GCC, aarch64)` | Debug build: `-static -g -O0` into `hello-debug` |
| `Deploy hello-debug to board` | Builds `hello-debug`, then `scp` + `chmod +x` to `/home/root/apps/` |
| `Start gdbserver on board` | Deploys first, then runs `gdbserver :2345 /home/root/apps/hello-debug` over SSH (kills any older `gdbserver` first). Runs as a background task; VS Code treats the line `Listening on port 2345` as "ready" |

The task chain is: `Build hello-debug` -> `Deploy hello-debug to board` -> `Start gdbserver on board`.

Important detail: the tasks run through **Git's bash** by full path (`C:\Users\<you>\AppData\Local\Programs\Git\bin\bash.exe`), set once under `options.shell` at the top of the file. A plain `bash.exe` can resolve to `C:\WINDOWS\system32\bash.exe`, which is the **WSL** launcher and would break the tasks.

### 4.2 Launch config: [.vscode/launch.json](.vscode/launch.json)

```json
{
    "name": "Debug hello on RZG2L (gdbserver)",
    "type": "cppdbg",
    "request": "launch",
    "program": "${workspaceFolder}/hello-debug",
    "cwd": "${workspaceFolder}",
    "stopAtEntry": true,
    "MIMode": "gdb",
    "miDebuggerPath": "C:/toolchains/bin/aarch64-none-linux-gnu-gdb.exe",
    "miDebuggerServerAddress": "10.0.0.121:2345",
    "preLaunchTask": "Start gdbserver on board",
    "setupCommands": [ { "text": "-enable-pretty-printing", "ignoreFailures": true } ]
}
```

- `program` is the **local** copy of `hello-debug` (with symbols); it must be the same build as the one on the board. The `preLaunchTask` chain guarantees this.
- `miDebuggerServerAddress` is where gdb connects: `<board-ip>:2345`.
- `stopAtEntry: true` stops at the start of `main`.

### 4.3 Disable the Renesas Tracing and Profiling extension for this workspace

If the **Renesas Tracing and Profiling Tools** extension (`renesas-rpm`) is enabled, every debug session (even a plain `cppdbg` one) fails immediately with:

```
Stopping due to fatal error: InvalidOperationException: No handler registered for request of type 'renesas/get_cores'!
```

That extension sends a Renesas-only request (`renesas/get_cores`) to all debug sessions, and the Microsoft C/C++ debug adapter doesn't understand it.

Fix:

1. Extensions view (`Ctrl+Shift+X`), search **Renesas Tracing and Profiling Tools**.
2. Gear icon -> **Disable (Workspace)**.
3. Run **Developer: Reload Window** (or restart VS Code). The extension host must actually restart; disabling alone isn't enough.

Other Renesas extensions don't depend on it, and other workspaces keep it enabled.

### 4.4 clangd editor errors (optional)

If clangd reports `'stdio.h' file not found` or `Call to undeclared library function 'printf'`, it is analysing `hello.c` as a Windows host file. [.clangd](.clangd) gives it the same target and sysroot as the cross-compiler:

```yaml
CompileFlags:
  Add:
    - --target=aarch64-none-linux-gnu
    - --sysroot=C:/toolchains/aarch64-none-linux-gnu/libc
```

Then run **Clangd: Restart language server**.

## 5. Start a debug session

1. Open [hello.c](hello.c) and click in the gutter to set a breakpoint (for example on the `printf` line).
2. Open **Run and Debug** (`Ctrl+Shift+D`), select **Debug hello on RZG2L (gdbserver)**, press the green play button (or `F5`).
3. VS Code builds, deploys, starts `gdbserver` on the board, and attaches. The program stops at the beginning of `main`.
4. Use the usual controls: Continue `F5`, Step Over `F10`, Step Into `F11`, plus the Variables, Watch, Call Stack and Disassembly panes.

Where to look:

- The program's own output (`Hello, World from RZG2L!`) appears in the **terminal of the `Start gdbserver on board` task**, not in the Debug Console. It shows up once you let the program run past `printf`.
- After the program ends, gdbserver prints `Child exited with status 0`. Press any key to close the task terminal ("Terminal will be reused by tasks" is normal).

## 6. Debug without VS Code (terminal)

Useful to isolate problems, or for a full-screen text UI (gdb TUI).

```bash
# Terminal 1: start gdbserver on the board with the debug binary
ssh root@<board-ip> '/home/root/apps/gdbserver :2345 /home/root/apps/hello-debug'

# Terminal 2: build locally and attach with the cross gdb
source /c/toolchains/env.sh
aarch64-none-linux-gnu-gcc -static -g -O0 -o hello-debug hello.c
aarch64-none-linux-gnu-gdb -tui -ex "target remote <board-ip>:2345" hello-debug
```

Inside gdb: `break main`, `continue`, `next`, `step`, `bt`, `info locals`, `print <var>`, `quit`.

Scripted (non-interactive) smoke test:

```bash
aarch64-none-linux-gnu-gdb -batch -ex "target remote <board-ip>:2345" \
  -ex "break main" -ex "continue" -ex "bt" -ex "continue" hello-debug
```

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Unable to negotiate ... no matching host key type found. Their offer: ssh-rsa` | Add the `HostKeyAlgorithms +ssh-rsa` / `PubkeyAcceptedAlgorithms +ssh-rsa` block for the board in `~/.ssh/config` (see [ether_readme.md](ether_readme.md), section 1) |
| `No handler registered for request of type 'renesas/get_cores'` | Renesas Tracing and Profiling extension is active. See [section 4.3](#43-disable-the-renesas-tracing-and-profiling-extension-for-this-workspace); remember to **reload the window** |
| Debugger can't connect / times out | `gdbserver` isn't running or the IP/port is wrong. Run the `Start gdbserver on board` task and look for `Listening on port 2345`; check `miDebuggerServerAddress` and that port 2345 isn't blocked |
| `Address already in use` on the board | An old `gdbserver` is still running: `ssh root@<board-ip> 'kill $(pidof gdbserver)'` (the task already does this) |
| Breakpoints don't bind / source not found | The local `hello-debug` and the one on the board differ. Re-run the deploy task; don't debug the `-O2` `hello` binary |
| Tasks fail with odd path errors | A plain `bash.exe` resolved to the WSL launcher. Keep the full Git bash path in `tasks.json` |
| `wsl ... bash /mnt/c/...` fails with a mangled `C:/Users/.../Git/mnt/c/...` path | Git Bash rewrites Unix-style paths. Prefix with `MSYS_NO_PATHCONV=1`. Also note that background jobs started with `&` inside a single `wsl` call are killed when the call returns |
| clangd: `'stdio.h' file not found` | See [section 4.4](#44-clangd-editor-errors-optional) |
| gdb warning `could not convert 'main' from the host encoding (CP1252) to UTF-32` | Harmless |
| `Unable to load schema from ... launch.schema.json: 404` | VS Code editor warning about its built-in schema URL; harmless. Updating VS Code removes it |
| Building `gdbserver` in Git Bash hangs or fails with `no usable dependency style found` | Don't build natively on Windows; use WSL (section 2) |

## 8. Things hardcoded to your PC

If the board IP, user name or install paths change, update these:

| Value | Where |
|---|---|
| Board IP `10.0.0.121` | [.vscode/tasks.json](.vscode/tasks.json) (5 places in 3 tasks), [.vscode/launch.json](.vscode/launch.json) (`miDebuggerServerAddress`), and the `Host` entry in `~/.ssh/config` |
| Git bash path `C:\Users\a5139629\AppData\Local\Programs\Git\bin\bash.exe` | [.vscode/tasks.json](.vscode/tasks.json) (`options.shell.executable`) |
| Toolchain root `C:\toolchains` | [.vscode/tasks.json](.vscode/tasks.json) (via `/c/toolchains/env.sh`), [.vscode/launch.json](.vscode/launch.json) (`miDebuggerPath`), [.clangd](.clangd) |
| `gdbserver` location on the board `/home/root/apps/gdbserver` and port `2345` | [.vscode/tasks.json](.vscode/tasks.json) (`Start gdbserver on board`) |
