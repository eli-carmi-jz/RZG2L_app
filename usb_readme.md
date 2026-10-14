# RZG2L Hello World — Build, Deploy & Run over serial + USB (no Ethernet)

Builds a statically-linked aarch64 "Hello World" on Windows (no WSL, no Yocto image build) and deploys it to the RZG2L board **without any network**: a UART console on the PC plus a second serial port created over the board's micro-USB cable. Use this where Ethernet isn't available.

**Board**: Renesas SMARC EVK (`r9a07g044l2`), BSP 3.0.6-update2, kernel 5.10.201-cip41, aarch64, root login (**no password**).

```
 PC (Windows)                                     RZG2L board
 ───────────────                                  ──────────────────────────
 <console-port>  <── USB-UART adapter (CP210x) ──────────> /dev/ttySC0   console / shell
 <usb-port>      <── micro-USB cable (g_serial gadget) ──> /dev/ttyGS0   binary transfer, gdbserver
```

> **COM port names.** `<console-port>` and `<usb-port>` stand for the COM ports Windows assigned on your PC. `COM12` and `COM14` are only the examples from the PC used while setting this up; yours will differ. See [section 1](#1-hardware-and-connections) for how to find them and [section 8](#8-things-hardcoded-to-your-pc) for where to enter them.

## Table of contents

1. [Hardware and connections](#1-hardware-and-connections)
2. [Why not USB Ethernet](#2-why-not-usb-ethernet)
3. [Toolchains and build](#3-toolchains-and-build)
4. [The helper scripts](#4-the-helper-scripts)
5. [Deploy & run on the board](#5-deploy--run-on-the-board)
6. [Day-to-day workflow](#6-day-to-day-workflow)
7. [Troubleshooting](#7-troubleshooting)
8. [Things hardcoded to your PC](#8-things-hardcoded-to-your-pc)

For debugging see [usb_debug_readme.md](usb_debug_readme.md).

## 1. Hardware and connections

| Link | Cable | PC side | Board side | Used for |
|---|---|---|---|---|
| Console (UART) | 4-wire cable on the UART header next to the Ethernet jack, to a USB-UART adapter (Silicon Labs CP210x) | `<console-port>` (e.g. `COM12`), 115200 8N1, no flow control | `/dev/ttySC0` | Login shell, running programs, seeing output |
| USB data | micro-USB cable from the board's micro-USB port to a PC USB port | `<usb-port>` (e.g. `COM14`) | `/dev/ttyGS0` (USB gadget) | Fast file copy and `gdbserver` |

Notes:

- On the UART cable connect only **GND, TX and RX**. If the adapter has a VCC/power wire, leave it unconnected to the board.
- The console login is `root` with **no password**. If the console shows `login:` type `root`. If it shows `Password:` after you typed something else, press `Ctrl+C` and start again.
- The COM numbers are assigned by Windows and differ from PC to PC (the examples `COM12`/`COM14` come from the PC used for this setup). Find yours with (PowerShell, or Device Manager > Ports):
  ```powershell
  Get-PnpDevice -Class Ports -PresentOnly | Select FriendlyName
  ```
  From Git bash, wrap it in `powershell`:
  ```bash
  powershell -NoProfile -Command "Get-PnpDevice -Class Ports -PresentOnly | Select FriendlyName"
  ```
  To also see the hardware IDs (to tell the USB gadget `VID_0525` from other devices), use `Select FriendlyName,InstanceId`.
  The console is the **Silicon Labs CP210x** entry (or whatever USB-UART adapter you use). The USB data port is a **USB Serial Device** with hardware ID `VID_0525` (appears after the board's gadget is loaded, see below). Other "USB Serial Device" entries, such as the internal Intel ones (`VID_8087`) on the PC used here, are **not** the board and report `Access ... denied` when opened.
- A COM port can be opened by **one program at a time**. Close SecureCRT (or PuTTY, etc.) before running the VS Code tasks, or the scripts fail with `Access to the port '<console-port>' is denied`.

### Board-side USB gadget

The board's USB controller (`11c60000.usb`) can act as a USB device. The kernel provides the modules, so no rebuild is needed. The `g_serial` module makes `/dev/ttyGS0` and Windows sees a COM port:

```bash
modprobe g_serial
stty -F /dev/ttyGS0 raw -echo -ixon -ixoff -crtscts
cat /sys/class/udc/11c60000.usb/state     # "configured" = the PC has enumerated it
```

This is **not persistent**: it is lost on reboot. The `USB: Init board link` task (see section 4) redoes it automatically.

## 2. Why not USB Ethernet

`g_ether` (RNDIS) also loads on the board and would give a normal network link (`ssh`, `scp`, TCP `gdbserver`). On the PC used here, however, Windows bound the gadget to its generic *USB Serial Device* driver and the *Remote NDIS Compatible Device* driver was not selectable in Device Manager. So the USB cable is used as a plain serial port instead. If RNDIS works on your PC (this needs admin rights to install the driver), the board can be reached over a USB network link (`modprobe g_ether`, then for example `ip addr add 192.168.7.2/24 dev usb0` on the board) and normal `ssh`/`scp`/TCP `gdbserver` can be used instead of the scripts in this guide.

## 3. Toolchains and build

### 3.1 Install the cross-compilers (native Windows, no WSL)

Two independent aarch64 cross-toolchains are installed under `C:\toolchains` (outside the repo, reusable by other projects). **The Arm GNU Toolchain (GCC) is required; LLVM/Clang is optional**, either one builds the same program. Run all commands below in Git bash.

**Requirements**

| Item | Notes |
|---|---|
| Windows 10/11, 64-bit, with Git for Windows | Provides Git bash, `curl`, `sed`, `rm` |
| Disk space | About 1 GB for the Arm GNU Toolchain (350 MB download); about 4 GB for LLVM (900 MB download) |
| `C:\Windows\System32\tar.exe` | Built into Windows 10/11 (bsdtar). Extracts `.zip` and `.tar.xz`. Git bash's own `tar` can't unpack `.zip`, and `unzip` isn't included |
| Internet access | To `developer.arm.com` and `github.com` |

**Step 1 — Arm GNU Toolchain 14.3.Rel1 (GCC, gdb, target sysroot)**

On the [Arm GNU Toolchain downloads](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads) page pick release **14.3.Rel1**, host **Windows (mingw-w64-i686)**, target **AArch64 GNU/Linux target (aarch64-none-linux-gnu)**. The file is `arm-gnu-toolchain-14.3.rel1-mingw-w64-i686-aarch64-none-linux-gnu.zip`. ("i686" only describes the host programs; they run on 64-bit Windows.) Or download and extract it from Git bash:

```bash
mkdir -p /c/toolchains && cd /c/toolchains
curl -L --fail -o arm-gnu.zip \
  "https://developer.arm.com/-/media/Files/downloads/gnu/14.3.rel1/binrel/arm-gnu-toolchain-14.3.rel1-mingw-w64-i686-aarch64-none-linux-gnu.zip"
/c/Windows/System32/tar.exe -xf arm-gnu.zip --strip-components=1 -C "C:/toolchains"
rm arm-gnu.zip
```

The zip has one top-level folder; `--strip-components=1` puts its contents directly into `C:\toolchains`. Check that `C:\toolchains\bin\aarch64-none-linux-gnu-gcc.exe` exists; if everything ended up in a subfolder instead, move it up one level.

Resulting layout:

| Path | Content |
|---|---|
| `C:\toolchains\bin\` | `aarch64-none-linux-gnu-gcc.exe`, `-g++`, `-gdb`, `-strip`, ... |
| `C:\toolchains\aarch64-none-linux-gnu\libc\` | Target sysroot (headers and libraries) |
| `C:\toolchains\lib\gcc\aarch64-none-linux-gnu\14.3.1\` | libgcc and crt startup objects |
| `C:\toolchains\libexec\` | Compiler internals (`cc1`, linker helpers) |

**Step 2 — LLVM/Clang 23.1.3 (optional)**

Take the Windows asset `clang+llvm-23.1.3-x86_64-pc-windows-msvc.tar.xz` from the [LLVM 23.1.3 release](https://github.com/llvm/llvm-project/releases/tag/llvmorg-23.1.3), or from Git bash:

```bash
mkdir -p /c/toolchains/llvm && cd /c/toolchains
curl -L --fail -o llvm.tar.xz \
  "https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.3/clang+llvm-23.1.3-x86_64-pc-windows-msvc.tar.xz"
/c/Windows/System32/tar.exe -xf llvm.tar.xz --strip-components=1 -C "C:/toolchains/llvm"
rm llvm.tar.xz
```

This gives `C:\toolchains\llvm\bin\clang.exe`, `clang++.exe`, `lld`, `llvm-readelf.exe` and `clangd.exe`.

**Step 3 — Clang wrapper scripts (only with Clang)**

Clang has no aarch64-linux sysroot of its own, so the wrapper points it at the Arm toolchain's sysroot and libgcc and selects the `lld` linker:

```bash
mkdir -p /c/toolchains/wrappers
cat > /c/toolchains/wrappers/aarch64-clang <<'EOF'
#!/usr/bin/env bash
TOOLCHAINS="/c/toolchains"
exec "$TOOLCHAINS/llvm/bin/clang.exe" \
  --target=aarch64-none-linux-gnu \
  --sysroot="$TOOLCHAINS/aarch64-none-linux-gnu/libc" \
  -B"$TOOLCHAINS/lib/gcc/aarch64-none-linux-gnu/14.3.1" \
  -L"$TOOLCHAINS/lib/gcc/aarch64-none-linux-gnu/14.3.1" \
  -fuse-ld=lld \
  "$@"
EOF
sed 's/clang\.exe/clang++.exe/' /c/toolchains/wrappers/aarch64-clang > /c/toolchains/wrappers/aarch64-clang++
chmod +x /c/toolchains/wrappers/aarch64-clang /c/toolchains/wrappers/aarch64-clang++
```

**Step 4 — `env.sh` (PATH setup)**

```bash
cat > /c/toolchains/env.sh <<'EOF'
export PATH="/c/toolchains/wrappers:/c/toolchains/llvm/bin:/c/toolchains/bin:$PATH"
EOF
```

Run `source /c/toolchains/env.sh` in every new Git bash terminal that builds by hand. The VS Code tasks source it themselves.

**Step 5 — Verify**

```bash
source /c/toolchains/env.sh
aarch64-none-linux-gnu-gcc --version | head -1    # ... (Arm GNU Toolchain 14.3.Rel1 ...) 14.3.1
aarch64-clang --version | head -1                 # clang version 23.1.3 (only with Clang)
```

**Install folder:** `C:\toolchains` is hardcoded in `env.sh`, the wrapper scripts, [.vscode/tasks.json](.vscode/tasks.json), [.vscode/launch.json](.vscode/launch.json) and [.clangd](.clangd). If you install elsewhere, update them all.

**Why static linking:** the generic toolchain's glibc doesn't exactly match the board's older Yocto glibc. `-static` avoids any ABI or version mismatch without needing the BSP's own Yocto SDK.

### 3.2 Write and build Hello World

[hello.c](hello.c) is a minimal `printf` program:

```c
#include <stdio.h>

int main(void)
{
    printf("Hello, World from RZG2L!\n");
    return 0;
}
```

```bash
source /c/toolchains/env.sh
aarch64-none-linux-gnu-gcc -static -O2 -o hello hello.c            # release (GCC)
aarch64-clang -static -O2 -o hello-clang hello.c                   # release (Clang, optional)
aarch64-none-linux-gnu-gcc -static -g -O0 -o hello-debug hello.c   # debug build, used for debugging
```

Check that the result is an AArch64 binary: `llvm-readelf -h hello | grep Machine` shows `AArch64`.

### 3.3 VS Code build tasks

[.vscode/tasks.json](.vscode/tasks.json) has these build tasks (GCC is the default build task, `Ctrl+Shift+B`):

| Task | Output |
|---|---|
| `Build hello (GCC, aarch64)` | `hello` (`-static -O2`) |
| `Build hello (Clang, aarch64)` | `hello-clang` |
| `Build hello-debug (GCC, aarch64)` | `hello-debug` (`-static -g -O0`) |

The tasks run through **Git's bash** by its full path (`C:\Users\<you>\AppData\Local\Programs\Git\bin\bash.exe`), set once under `options.shell` at the top of the file. A plain `bash.exe` can resolve to `C:\WINDOWS\system32\bash.exe`, which is the **WSL** launcher and breaks the tasks. The file also sets `MSYS_NO_PATHCONV=1`, so Git bash does not rewrite arguments such as `/home/root/apps/hello` into Windows paths.

### 3.4 clangd editor errors (optional)

If the clangd extension reports `'stdio.h' file not found` or `Call to undeclared library function 'printf'`, it is analysing `hello.c` as a Windows host file. [.clangd](.clangd) gives it the same target and sysroot as the cross-compiler:

```yaml
CompileFlags:
  Add:
    - --target=aarch64-none-linux-gnu
    - --sysroot=C:/toolchains/aarch64-none-linux-gnu/libc
```

Then run **Clangd: Restart language server**.

## 4. The helper scripts

All in [scripts](scripts). They are PowerShell (using .NET `System.IO.Ports`), so no extra software is needed on the PC. The board needs only `python3` and `sha256sum`, which the image already has.

| Script | What it does |
|---|---|
| [console.ps1](scripts/console.ps1) | Types one command on the console (`<console-port>`) and prints what the board answers |
| [usb-init.ps1](scripts/usb-init.ps1) | Stops old `gdbserver`/receiver processes, unloads `g_ether` if present, loads `g_serial`, sets `/dev/ttyGS0` to raw, checks that the PC is connected, and installs `recv.py` on the board if missing |
| [usb-deploy.ps1](scripts/usb-deploy.ps1) | Starts `recv.py` on the board through the console, then sends a file to `/home/root/apps/<name>` over `<usb-port>` |
| [usb-send.ps1](scripts/usb-send.ps1) | The PC half of the transfer: header `SIZE <bytes> <dest>`, the raw bytes, then checks the SHA-256 reported by the board |
| [recv.py](scripts/recv.py) | Runs on the board: reads one file from `/dev/ttyGS0`, writes it, makes it executable, replies `OK <sha256>` |
| [put-console.ps1](scripts/put-console.ps1) | Bootstrap only: copies a small text file through the console as base64 (used once to install `recv.py`) |
| [test-usb.gdb](scripts/test-usb.gdb) | Non-interactive gdb session used to test debugging (see the debug guide) |

Run any of them from the workspace folder, for example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/console.ps1 -Cmd 'uname -a'
```

### VS Code tasks ([.vscode/tasks.json](.vscode/tasks.json))

| Task | What it does |
|---|---|
| `USB: Init board link` | Runs `usb-init.ps1` |
| `USB: Deploy & run hello on board` | Builds `hello` (GCC), runs init, sends `hello` over USB, then runs it through the console |
| `USB: Deploy hello-debug to board` | Builds `hello-debug`, runs init, sends it over USB |
| `USB: Start gdbserver on board` | Deploys `hello-debug`, then starts `gdbserver` on `/dev/ttyGS0` (see [usb_debug_readme.md](usb_debug_readme.md)) |

The tasks run through Git bash with `MSYS_NO_PATHCONV=1` set, so arguments such as `/home/root/apps/hello` are not rewritten into Windows paths.

## 5. Deploy & run on the board

One-time check: the board console is logged in as `root` (open SecureCRT on `<console-port>` if you want to look, then close it again).

From VS Code run **Terminal > Run Task > USB: Deploy & run hello on board**. Or by hand in Git Bash:

```bash
export MSYS_NO_PATHCONV=1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/usb-init.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/usb-deploy.ps1 -Src hello
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/console.ps1 -Cmd '/home/root/apps/hello'
```

Expected: `sent 2840960 bytes, sha256 ok` (about 2.8 MB for the static binary), then `Hello, World from RZG2L!`.

The programs print to the console, so their output is also visible in a terminal program on `<console-port>`.

## 6. Day-to-day workflow

1. Plug in the UART adapter and the micro-USB cable; power the board; make sure no terminal program holds `<console-port>`.
2. Edit [hello.c](hello.c).
3. Run **USB: Deploy & run hello on board** (it builds, initialises the link, copies, and runs).
4. To debug, press `F5` with **Debug hello on RZG2L (USB serial COM14)** selected (see [usb_debug_readme.md](usb_debug_readme.md)). The config name contains the example port; rename it if yours differs.

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Access to the port '<console-port>' is denied` (or `<usb-port>`) | Another program holds the port (SecureCRT, a previous gdb, a stuck PowerShell). Close it. Internal devices such as Intel "USB Serial Device" entries always report this; they are not the board |
| `USB gadget not connected: plug the micro-USB cable into the PC` | The board's UDC state is not `configured`. Check the micro-USB cable and port, then run `USB: Init board link` again |
| No `<usb-port>` in Device Manager (it is greyed out/"Unknown" with `Get-PnpDevice`), even after replugging the cable or rebooting the board | `g_serial` isn't loaded: the gadget is lost on every reboot, so the port only exists while the board has it loaded. Either run `USB: Init board link` (close SecureCRT first, it holds `<console-port>`), or type on the board console: `modprobe g_serial` and `cat /sys/class/udc/11c60000.usb/state` (should print `configured`). The COM number may also differ if you use another USB port; update it (section 8) |
| Console prints nothing | Wrong COM port, or the board isn't booted. Press Enter on `<console-port>`; check that TX and RX are not swapped and GND is connected |
| Console shows `Password:` | A command was typed at the `login:` prompt. Press `Ctrl+C`, then type `root` |
| Console session logged out (`logout`) | Something HUPed the shell, for example starting `gdbserver` directly from the console. The tasks use `setsid ... < /dev/null > /dev/console &` for this reason |
| `transfer failed: ... (expected <hash>)` | The receiver wasn't running or the cable dropped. Run `USB: Init board link` (it restarts `recv.py`) and retry |
| Write timeout in `usb-send.ps1` | `recv.py` isn't listening on the board. `usb-deploy.ps1` starts it; if it crashes, read `/tmp/recv.log` on the board |
| `ModuleNotFoundError: No module named 'hashlib'` | The board's Python is minimal. `recv.py` already uses `sha256sum` instead; don't add `hashlib` |
| `timeout: command not found` on the board | The image has no `timeout`. Use a background process and `kill` instead |
| A path like `C:/Program Files/Git/home/root/...` is sent to the board | Git Bash rewrote `/home/root/...`. Set `MSYS_NO_PATHCONV=1` (the tasks already do) |
| Build tasks fail with odd path errors | A plain `bash.exe` resolved to the WSL launcher. Keep the full Git bash path in `tasks.json` (section 3.3) |
| clangd: `'stdio.h' file not found` | See section 3.4 |

## 8. Things hardcoded to your PC

| Value | Where |
|---|---|
| Console port (`<console-port>`, e.g. `COM12`) | Default `-Port` / `-Console` in [scripts/console.ps1](scripts/console.ps1), [scripts/put-console.ps1](scripts/put-console.ps1), [scripts/usb-init.ps1](scripts/usb-init.ps1), [scripts/usb-deploy.ps1](scripts/usb-deploy.ps1) |
| USB data port (`<usb-port>`, e.g. `COM14`) | Default `-Port` / `-Data` in [scripts/usb-send.ps1](scripts/usb-send.ps1), [scripts/usb-deploy.ps1](scripts/usb-deploy.ps1); `miDebuggerServerAddress` in [.vscode/launch.json](.vscode/launch.json); [scripts/test-usb.gdb](scripts/test-usb.gdb) |
| Board paths `/home/root/apps`, `/home/root/recv.py` | [scripts/usb-deploy.ps1](scripts/usb-deploy.ps1), [scripts/usb-init.ps1](scripts/usb-init.ps1), [.vscode/tasks.json](.vscode/tasks.json) |
| UDC name `11c60000.usb` | [scripts/usb-init.ps1](scripts/usb-init.ps1) |
| Git bash path, toolchain root `C:\toolchains` | [.vscode/tasks.json](.vscode/tasks.json), [.vscode/launch.json](.vscode/launch.json) |
