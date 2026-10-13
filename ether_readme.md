# RZG2L Hello World — Cross-compile & Deploy

Builds a statically-linked aarch64 "Hello World" on Windows (no WSL, no Yocto image build) and deploys it to the RZG2L SMARC EVK board over SSH.

**Board**: RZG2L SMARC EVK, BSP 3.0.6-update2, kernel 5.10.201-cip41, aarch64, root login (no password).

> No Ethernet available? Use the serial + USB flow in [usb_readme.md](usb_readme.md).

**Connectivity**: the board is reached over the network via SSH/SCP (Ethernet, has an IP address on the LAN). It also has a serial console port (UART), currently unused for this workflow, available at `115200 8N1` (115200 baud, 8 data bits, no parity, 1 stop bit, no flow control) if network access is ever unavailable.

**Setting/checking the board's IP** (run on the board itself, e.g. over the serial console or an existing login — `eth1` is the active interface seen in the boot log):
```bash
# check current IP
ip addr show eth1

# get an IP automatically via DHCP
udhcpc -i eth1

# or set a static IP temporarily (replace with your subnet/gateway)
ip addr add 10.0.0.121/24 dev eth1
ip link set eth1 up
ip route add default via 10.0.0.1
```
These changes are not persistent across reboots unless written into the board's network config (e.g. `/etc/systemd/network/`, connman, or `/etc/network/interfaces`, depending on the image).

> Replace `<board-ip>` below with your board's actual IP address (e.g. `10.0.0.121` is just the example used while setting this up — it can be different on your network).

## Table of contents

1. [Fix SSH connectivity](#fix-ssh-connectivity)
2. [Toolchains and build](#toolchains-and-build)
   - 2.1 [Install the cross-compilers (native Windows, no WSL)](#21-install-the-cross-compilers-native-windows-no-wsl)
   - 2.2 [Write and build Hello World](#22-write-and-build-hello-world)
   - 2.3 [VS Code build tasks](#23-vs-code-build-tasks)
   - 2.4 [clangd editor errors (optional)](#24-clangd-editor-errors-optional)
3. [Deploy & run on the board](#deploy--run-on-the-board)
4. [Day-to-day workflow](#day-to-day-workflow)
5. [Notes / future considerations](#notes--future-considerations)

<a id="fix-ssh-connectivity"></a>
## 1. Fix SSH connectivity

Modern OpenSSH clients (8.8+) disable the `ssh-rsa` host key algorithm by default, but the board's SSH server only offers an RSA host key, causing:
```
Unable to negotiate with <board-ip> port 22: no matching host key type found. Their offer: ssh-rsa
```

Fix: added a `Host <board-ip>` block to `~/.ssh/config` (client-side only, nothing changed on the board). Example used here with IP `10.0.0.121`:
```
Host 10.0.0.121
  HostKeyAlgorithms +ssh-rsa
  PubkeyAcceptedAlgorithms +ssh-rsa
```
Verified with `ssh root@<board-ip> uname -a` (e.g. `ssh root@10.0.0.121 uname -a`).

<a id="toolchains-and-build"></a>
## 2. Toolchains and build

<a id="21-install-the-cross-compilers-native-windows-no-wsl"></a>
### 2.1 Install the cross-compilers (native Windows, no WSL)

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

<a id="22-write-and-build-hello-world"></a>
### 2.2 Write and build Hello World

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

<a id="23-vs-code-build-tasks"></a>
### 2.3 VS Code build tasks

[.vscode/tasks.json](.vscode/tasks.json) has these build tasks (GCC is the default build task, `Ctrl+Shift+B`):

| Task | Output |
|---|---|
| `Build hello (GCC, aarch64)` | `hello` (`-static -O2`) |
| `Build hello (Clang, aarch64)` | `hello-clang` |
| `Build hello-debug (GCC, aarch64)` | `hello-debug` (`-static -g -O0`) |

The tasks run through **Git's bash** by its full path (`C:\Users\<you>\AppData\Local\Programs\Git\bin\bash.exe`), set once under `options.shell` at the top of the file. A plain `bash.exe` can resolve to `C:\WINDOWS\system32\bash.exe`, which is the **WSL** launcher and breaks the tasks. The file also sets `MSYS_NO_PATHCONV=1`, so Git bash does not rewrite arguments such as `/home/root/apps/hello` into Windows paths.

<a id="24-clangd-editor-errors-optional"></a>
### 2.4 clangd editor errors (optional)

If the clangd extension reports `'stdio.h' file not found` or `Call to undeclared library function 'printf'`, it is analysing `hello.c` as a Windows host file. [.clangd](.clangd) gives it the same target and sysroot as the cross-compiler:

```yaml
CompileFlags:
  Add:
    - --target=aarch64-none-linux-gnu
    - --sysroot=C:/toolchains/aarch64-none-linux-gnu/libc
```

Then run **Clangd: Restart language server**.

<a id="deploy--run-on-the-board"></a>
## 3. Deploy & run on the board

```bash
# replace <board-ip> with your board's actual IP address, e.g. 10.0.0.121
scp hello hello-clang root@<board-ip>:/home/root/apps/
ssh root@<board-ip> 'chmod +x /home/root/apps/hello /home/root/apps/hello-clang
/home/root/apps/hello
/home/root/apps/hello-clang'
```
Both printed `Hello, World from RZG2L!` successfully (tested against the example IP `10.0.0.121`).

A "Deploy & run hello on board" task was added to [.vscode/tasks.json](.vscode/tasks.json) (builds with GCC, then scp + ssh chmod/run in one step).

<a id="day-to-day-workflow"></a>
## 4. Day-to-day workflow

1. Edit [hello.c](hello.c).
2. `Ctrl+Shift+B` to rebuild (GCC).
3. Run the **"Deploy & run hello on board"** task to copy and execute it on the board.

<a id="notes--future-considerations"></a>
## 5. Notes / future considerations

- The SSH fix is client-side only; the board's sshd/dropbear config was left untouched.
- If a future app needs dynamic linking, shared libraries, or an exact libc/ABI match, use the actual Yocto SDK generated for this BSP (`bitbake core-image-minimal -c populate_sdk`, or the BSP's SDK installer `.sh`) instead of static linking — that requires a Linux host or WSL.
