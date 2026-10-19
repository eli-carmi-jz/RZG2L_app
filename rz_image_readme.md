# Build and Write a Minimal Renesas RZ/G2L Linux BSP Plus Image

This guide describes how to build a minimal console Linux image for the **Renesas SMARC RZ/G2L** board, write it to a microSD card, and boot the board.

It is based on the official Renesas guide [How To Build Linux BSP Plus - Renesas RZ Linux BSP Plus](https://renesas-rz.github.io/rz_linux_bsp_plus/RZG/how_to_build_linux_bsp_plus/) and adds the fixes and host-specific steps found while building. If the official guide changes (for example the commit IDs or tags), check it for the current values.

The build can be done on any of these hosts:

- **A native Linux host**, such as a PC or VM running Ubuntu.
- **A remote Linux host** reached over SSH.
- **A Windows PC using WSL2** (Ubuntu running inside Windows).

The steps are the same for all hosts. Only the host preparation ([section 3](#3-prepare-the-build-host)) and the way the card is written ([section 17](#17-write-the-image-to-a-microsd-card)) differ.

Graphics and video codec layers are intentionally omitted from the minimal image, and [section 9.4](#94-optional-graphics-and-video-codec-layers) shows how to add them. All names, email addresses, hostnames, paths, device names, and timestamps are generic examples or placeholders.

## Table of contents

1. [Build overview](#1-build-overview)
2. [Host requirements](#2-host-requirements)
3. [Prepare the build host](#3-prepare-the-build-host)
4. [Install build dependencies](#4-install-build-dependencies)
5. [Configure the UTF-8 locale](#5-configure-the-utf-8-locale)
6. [Configure Git](#6-configure-git)
7. [Create the workspace](#7-create-the-workspace)
8. [Clone the source repositories](#8-clone-the-source-repositories)
9. [Choose optional features and target storage](#9-choose-optional-features-and-target-storage)
10. [Initialize the Yocto build environment](#10-initialize-the-yocto-build-environment)
11. [Verify the configured layers](#11-verify-the-configured-layers)
12. [Build the image](#12-build-the-image)
13. [Confirm that the build succeeded](#13-confirm-that-the-build-succeeded)
14. [Locate the generated artifacts](#14-locate-the-generated-artifacts)
15. [Resume or repeat the build](#15-resume-or-repeat-the-build)
16. [Build logs and troubleshooting](#16-build-logs-and-troubleshooting)
17. [Write the image to a microSD card](#17-write-the-image-to-a-microsd-card)
18. [Boot the board](#18-boot-the-board)

Appendices:

- [Appendix A: Condensed command sequence](#appendix-a-condensed-command-sequence)
- [Appendix B: Docker experiment and limitation](#appendix-b-docker-experiment-and-limitation)

---

## 1. Build overview

### 1.1 Target configuration

```text
Board/MACHINE:  smarc-rzg2l
Architecture:   AArch64, Cortex-A55
Distribution:   rz-bsp-plus
Distro version: 5.0.11
Image recipe:   core-image-minimal
BitBake:        2.8.0
```

### 1.2 Successful build result

```text
NOTE: Tasks Summary: Attempted 5909 tasks of which 5003 didn't need to be rerun and all succeeded.
Summary: There were 6 WARNING messages.
```

### 1.3 Primary microSD artifacts

```text
core-image-minimal-smarc-rzg2l.rootfs.wic.gz
core-image-minimal-smarc-rzg2l.rootfs.wic.bmap
```

### 1.4 Workflow

1. Check the host requirements (section 2) and prepare the host (section 3).
2. Install the dependencies, locale and Git identity (sections 4 to 6).
3. Create the workspace and clone the sources (sections 7 and 8).
4. Choose optional features (section 9), initialize the build environment (sections 10 and 11), and build (section 12).
5. Confirm and locate the artifacts (sections 13 and 14). Use sections 15 and 16 to resume a build or fix problems.
6. Write the card (section 17) and boot the board (section 18).

---

## 2. Host requirements

Identify the host:

```bash
uname -a
cat /etc/os-release
python3 --version
```

### 2.1 Supported operating systems

The official Renesas guide ([How To Build Linux BSP Plus](https://renesas-rz.github.io/rz_linux_bsp_plus/RZG/how_to_build_linux_bsp_plus/)) specifies a 64-bit **Ubuntu 22.04 LTS** host with about **110 GB** of free disk space. This image was also built successfully on:

| Host OS | Python | Result |
|---|---|---|
| Ubuntu 22.04 LTS (64-bit) | 3.10 | Officially specified; no workaround needed |
| Ubuntu 20.04 LTS (64-bit) | 3.8.x | Built successfully |
| Ubuntu 24.04 LTS-based (Linux Mint 22.3) | 3.12.3 | Built successfully |
| Ubuntu 24.04 LTS on WSL2 | 3.12.x | Built successfully, but needed the buildtools workaround in [section 10.1](#101-ubuntu-2404-only-install-and-activate-buildtools) |

On Ubuntu 24.04 the Yocto `pseudo` tool can fail with `tar` errors on some hosts. Section 10.1 gives the fix.

On the Linux Mint host, BitBake warned that the distribution (`linuxmint-22.3`) was not validated, but the build completed. Other Ubuntu-based 64-bit distributions will probably work the same way.

### 2.2 Resource requirements

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 4 cores | 8 or more cores |
| RAM | 8 GB, with [reduced parallelism](#122-limit-parallelism-on-low-ram-hosts) | 16 GB or more |
| Free disk space | About 110 GB | 150 GB or more |
| Swap | 2 GB | 8 GB or more on hosts with less than 16 GB RAM |
| Network | Internet access to GitHub, `yoctoproject.org` and `openembedded.org` | |
| Python | 3.8 or newer | |
| Filesystem | Case-sensitive Linux filesystem | |

Do not build under a Windows-mounted directory such as `/mnt/c`. On WSL2, build in the Linux home directory (see [section 3.3](#33-windows-host-with-wsl2)).

Check the host before starting:

```bash
nproc
free -h
df -h "$HOME"
```

On a host with less than 16 GB RAM, the default BitBake parallelism can exhaust memory and the kernel kills a compiler or `git` process, which fails the build. See [section 12.2](#122-limit-parallelism-on-low-ram-hosts) and [section 16.6](#166-out-of-memory-oom-failures).

---

## 3. Prepare the build host

Complete only the subsection that matches your host. A native Linux host or VM that already meets section 2 needs no preparation; continue with section 4.

| Host | Do |
|---|---|
| Native Linux PC or VM | Nothing. Continue with [section 4](#4-install-build-dependencies). |
| Remote Linux host | [Section 3.2](#32-remote-linux-host-ssh), then [section 3.4](#34-keep-the-build-running-after-disconnecting). |
| Windows PC | [Section 3.3](#33-windows-host-with-wsl2). |

### 3.1 Which host to use

For the lowest risk, use Ubuntu 22.04 LTS (64-bit) with at least 16 GB RAM and 150 GB free disk. Other combinations that were verified are listed in [section 2.1](#21-supported-operating-systems).

### 3.2 Remote Linux host (SSH)

This is only required when the Linux build host will be accessed remotely.

Install SSH on the host:

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
sudo systemctl status ssh
```

If UFW is enabled, allow SSH:

```bash
sudo ufw allow ssh
sudo ufw status
```

Find the host address:

```bash
ip addr
```

Optional checks:

```bash
ping -c 4 8.8.8.8
systemctl status ssh
```

XRDP is optional and is not required for the Yocto build.

### 3.3 Windows host with WSL2

Use this when the only available machine is a Windows PC. The Yocto build runs in an Ubuntu distribution under WSL2. Sections 4 to 16 are then run **inside the WSL Ubuntu shell**, exactly as on a native Linux host. The image is written to the card from Windows ([section 17.9](#179-write-the-image-from-windows)).

#### 3.3.1 Windows requirements

| Item | Requirement |
|---|---|
| Windows | Windows 10 (22H2) or Windows 11, 64-bit |
| Free disk space | At least 110 GB on the drive that holds the WSL distribution (more is better) |
| RAM | 16 GB recommended (8 GB minimum, with swap and [reduced parallelism](#122-limit-parallelism-on-low-ram-hosts)) |
| CPU | 4 or more cores. The first build takes several hours. |
| Virtualization | Enabled in BIOS/UEFI (Intel VT-x or AMD-V) |
| Hardware | microSD card (8 GB or larger) and a reader, RZ/G2L SMARC EVK, USB-C power supply, USB cable for the serial console |
| Network | Internet access (the build downloads several GB of sources) |

#### 3.3.2 Choose the Ubuntu version

| Option | Version | Status |
|---|---|---|
| **Recommended** | **Ubuntu 22.04 LTS, 64-bit** | The version required by the [official Renesas guide](https://renesas-rz.github.io/rz_linux_bsp_plus/RZG/how_to_build_linux_bsp_plus/). Builds without workarounds. |
| Verified with workaround | Ubuntu 24.04 LTS | Fails with `pseudo` errors unless you apply [section 10.1](#101-ubuntu-2404-only-install-and-activate-buildtools). Completed successfully with the workaround. |

List the distributions that can be installed (PowerShell):

```powershell
wsl --list --online
```

#### 3.3.3 Install WSL2 and Ubuntu

Run these commands in **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu-22.04
```

For Ubuntu 24.04 use `wsl --install -d Ubuntu-24.04` instead, and apply section 10.1 later.

Reboot if asked. On first launch of the distribution, create a Linux user name and password. If WSL is already installed, this adds a second, separate distribution and leaves your existing one untouched.

#### 3.3.4 Update WSL

```powershell
wsl --update
wsl --shutdown
wsl --version
```

#### 3.3.5 Check that the distribution runs as WSL2

```powershell
wsl -l -v
```

The `VERSION` column must show `2`. If it shows `1`, convert it:

```powershell
wsl --set-version <distro-name> 2
```

#### 3.3.6 Set resource limits

WSL2 uses only part of the Windows RAM by default, which can cause the out-of-memory failures described in [section 16.6](#166-out-of-memory-oom-failures). Create or edit `C:\Users\<your-user>\.wslconfig` and size it for your PC (the values below suit a 32 GB PC; use about half of the Windows RAM or more):

```ini
[wsl2]
memory=16GB
processors=8
swap=16GB
```

Apply it:

```powershell
wsl --shutdown
```

#### 3.3.7 Start the distribution and continue

Open the distribution:

```powershell
wsl -d <distro-name>
```

Inside it, check the version and free space:

```bash
lsb_release -a
uname -a
df -h ~
```

Always work in the Linux filesystem (for example `~/RZG2L`). **Do not build under `/mnt/c`**: it is slow and breaks file permissions.

Now continue with [section 4](#4-install-build-dependencies) and run every following build step inside this WSL shell. WSL-specific notes:

- Keep the PC awake and the WSL window open during the build. If it stops, run the same `bitbake` command again and it resumes.
- Copy files from Windows through `/mnt/c/Users/<your-user>/...` (for example the Graphics and Codec zip files in [section 9.4](#94-optional-graphics-and-video-codec-layers)).
- Copy the finished image to Windows as described in [section 14.3](#143-copy-the-image-to-windows-wsl2).
- WSL problems are listed in the table in [section 16.8](#168-other-common-problems).

### 3.4 Keep the build running after disconnecting

The build takes several hours. When working over SSH, run the commands in sections 10 to 12 inside `tmux` so that a dropped connection does not stop the build:

```bash
sudo apt install -y tmux
tmux new -s rzbuild          # start a session and run the build inside it
# Detach with Ctrl+b d, then reattach later with:
tmux attach -t rzbuild
```

To keep a log, run the build as `MACHINE=${BOARD} bitbake core-image-minimal 2>&1 | tee ~/rz_build.log`.

---

## 4. Install build dependencies

### 4.1 Update the host

```bash
sudo apt update
sudo apt upgrade -y
```

### 4.2 Install packages

```bash
sudo apt install -y \
  build-essential chrpath cpio debianutils diffstat file gawk gcc git \
  iputils-ping libacl1 liblz4-tool locales python3 python3-git \
  python3-jinja2 python3-pexpect python3-pip python3-subunit socat \
  texinfo unzip wget xz-utils zstd bmap-tools
```

### 4.3 Verify tools

```bash
python3 --version
git --version
tar --version
bmaptool --version
```

---

## 5. Configure the UTF-8 locale

BitBake refuses to start without a UTF-8 locale. The plain `C` and `POSIX` locales are not enough.

### 5.1 Generate the locale

```bash
sudo apt install -y locales
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8
```

### 5.2 Apply it to the current shell

```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
```

### 5.3 Verify it

```bash
locale
locale -a | grep en_US
```

Expected locale entry:

```text
en_US.utf8
```

Repeat the exports after opening a new shell unless they are added to the shell startup configuration:

```bash
echo 'export LANG=en_US.UTF-8' >> ~/.bashrc
echo 'export LC_ALL=en_US.UTF-8' >> ~/.bashrc
```

Run these two commands only once, or the lines are duplicated.

---

## 6. Configure Git

```bash
git config --global user.email "<your-email-address>"
git config --global user.name "<your-name>"
```

On a shared host, check the existing identity first (`git config --global --list`) and change it only if intended.

Verify:

```bash
git config --global --list
```

---

## 7. Create the workspace

Choose any directory with enough free space (see [section 2.2](#22-resource-requirements)). `~/RZG2L` is used as the example; replace it with your own path. All later commands use `$WORK`, so set it again in every new shell.

```bash
export WORK=~/RZG2L
export BOARD=smarc-rzg2l

mkdir -p "$WORK"
cd "$WORK"
```

Verify:

```bash
echo "$WORK"
echo "$BOARD"
```

---

## 8. Clone the source repositories

Use the exact revisions below to reproduce the successful build.

### 8.1 Poky

```bash
cd "$WORK"
git clone https://git.yoctoproject.org/git/poky
cd poky
git checkout -b tmp ae2d52758fc2fcb0ed996aa234430464ebf4b310
```

### 8.2 meta-arm

```bash
cd "$WORK"
git clone https://git.yoctoproject.org/meta-arm
cd meta-arm
git checkout -b tmp 8e0f8af90fefb03f08cd2228cde7a89902a6b37c
```

### 8.3 meta-openembedded

```bash
cd "$WORK"
git clone https://git.openembedded.org/meta-openembedded
cd meta-openembedded
git checkout -b tmp c29a18fa39ede952f3f6108ec007c1906e2d9a0d
```

### 8.4 meta-renesas

```bash
cd "$WORK"
git clone https://github.com/renesas-rz/meta-renesas
cd meta-renesas
git checkout -b tmp BSP-PLUS-K6.12-V2.0
```

These revisions are the ones in the [official Renesas guide](https://renesas-rz.github.io/rz_linux_bsp_plus/RZG/how_to_build_linux_bsp_plus/) at the time of writing. If the guide has been updated, use the newer values.

### 8.5 Verify the workspace

```bash
cd "$WORK"
ls -la
```

Expected directories:

```text
meta-arm
meta-openembedded
meta-renesas
poky
```

Verify revisions:

```bash
git -C poky rev-parse HEAD
git -C meta-arm rev-parse HEAD
git -C meta-openembedded rev-parse HEAD
git -C meta-renesas status --short --branch
```

---

## 9. Choose optional features and target storage

### 9.1 Minimal image without graphics or codecs

This guide does not use the proprietary graphics and codec packages for the minimal image:

```text
RTK0EF0045Z14001ZJ  Graphics
RTK0EF0045Z16002ZJ  Codec/video
```

Do not add the following layers for this minimal image:

```bash
# Not used by the minimal image
bitbake-layers add-layer ../meta-rz-features/meta-rz-graphics
bitbake-layers add-layer ../meta-rz-features/meta-rz-codecs
```

Use the feature packages only when GPU, Wayland/Weston, or video codec support is required. See [section 9.4](#94-optional-graphics-and-video-codec-layers).

### 9.2 microSD target

Build normally for a microSD card. The successful image documented here uses:

```text
core-image-minimal-smarc-rzg2l.rootfs.wic.gz
core-image-minimal-smarc-rzg2l.rootfs.wic.bmap
```

### 9.3 Internal eMMC target

The board's internal writable storage is eMMC, not ROM. After initializing the build environment (section 10) and before building for the Renesas eMMC workflow, add:

```bash
cd "${WORK}/build"
echo 'IMAGE_INSTALL:append = " e2fsprogs-mke2fs"' >> conf/local.conf
```

Run this once only. Then build or rebuild:

```bash
MACHINE=smarc-rzg2l bitbake core-image-minimal
```

The microSD image documented here was built without this eMMC-specific setting. Add the package and rebuild before following an eMMC installation procedure.

The output also includes bootloader variants named with `bl2_bp_esd`, `bl2_bp_mmc`, and `bl2_bp_spi`. Use only the variant required by the board-specific programming instructions.

### 9.4 Optional Graphics and Video Codec layers

Skip this section for the minimal image. It is needed for GPU acceleration, Wayland/Weston (`core-image-weston`) and video codecs. RZ/G2LC does not support the Video Codec package.

Download both packages from renesas.com (links are on the [official Renesas guide](https://renesas-rz.github.io/rz_linux_bsp_plus/RZG/how_to_build_linux_bsp_plus/)) and check the release note inside each:

| Package | Example archive name |
|---|---|
| Graphics | `RTK0EF0045Z14001ZJ-5.1.2.6_EN.zip` |
| Video Codec | `RTK0EF0045Z16002ZJ_v5.1.4.0-beta_EN.zip` |

Copy the zip files into `$WORK` (on WSL2 they are typically under `/mnt/c/Users/<your-user>/Downloads/`), then extract them:

```bash
cd "$WORK"
unzip RTK0EF0045Z14001ZJ-*.zip
tar zxvf RTK0EF0045Z14001ZJ-*/meta-rz-features_graphics_*.tar.gz

unzip RTK0EF0045Z16002ZJ_*.zip
tar zxvf RTK0EF0045Z16002ZJ_*/meta-rz-features_codec_*.tar.gz

ls "$WORK/meta-rz-features"
```

This creates `meta-rz-features/` with `meta-rz-graphics` and `meta-rz-codecs`.

Add the layers **after** initializing the build environment (section 10). Running `bitbake-layers` earlier fails with `command not found`:

```bash
cd "$WORK/build"
bitbake-layers add-layer ../meta-rz-features/meta-rz-graphics
bitbake-layers add-layer ../meta-rz-features/meta-rz-codecs
bitbake-layers show-layers
```

`show-layers` should then also list `meta-rz-graphics` and `meta-rz-codecs`. Add each layer only once. The image to build is then `core-image-minimal` (with the layers added) or `core-image-weston`.

---

## 10. Initialize the Yocto build environment

### 10.1 Ubuntu 24.04 only: install and activate buildtools

**Skip this section on Ubuntu 22.04 and 20.04.**

On some Ubuntu 24.04 hosts (it happened on WSL2 Ubuntu 24.04), BitBake fails in `do_package` tasks because the Yocto `pseudo` fakeroot does not cope with the host `tar` and glibc. The fix is to run the whole build inside the Yocto extended buildtools environment. The error is described in [section 16.7](#167-ubuntu-2404-pseudo-and-tar-errors).

Install buildtools once. The version in the file name must match the poky version (5.0.11):

```bash
cd "$WORK"
wget https://downloads.yoctoproject.org/releases/yocto/yocto-5.0.11/buildtools/x86_64-buildtools-extended-nativesdk-standalone-5.0.11.sh
chmod +x x86_64-buildtools-extended-nativesdk-standalone-5.0.11.sh
./x86_64-buildtools-extended-nativesdk-standalone-5.0.11.sh -y -d "$WORK/buildtools"
```

The installer prints `SDK has been successfully set up`.

Activate it in **every new shell, before** `oe-init-build-env` (section 10.3):

```bash
. "$WORK/buildtools/environment-setup-x86_64-pokysdk-linux"
which tar
```

`which tar` must print a path under `$WORK/buildtools/`. The version still shows 1.35, because the fix comes from the buildtools environment and not from an older `tar`.

### 10.2 Verify the template path

```bash
cd "$WORK"
find meta-renesas -type d | grep rz-bsp-plus-conf
```

Expected:

```text
meta-renesas/meta-rz-distro/conf/templates/rz-bsp-plus-conf
```

### 10.3 Initialize the build directory

```bash
cd "$WORK"

TEMPLATECONF=${PWD}/meta-renesas/meta-rz-distro/conf/templates/rz-bsp-plus-conf \
source poky/oe-init-build-env build
```

The shell should move to `$WORK/build`. On the first run, Yocto creates:

```text
build/conf/local.conf
build/conf/bblayers.conf
```

The `templates/bsp-plus-conf` directory named in the [official guide](https://renesas-rz.github.io/rz_linux_bsp_plus/RZG/how_to_build_linux_bsp_plus/) was not present in this checkout. For `BSP-PLUS-K6.12-V2.0`, use `templates/rz-bsp-plus-conf`.

After the first run, `build/conf` already exists and is reused, so the `TEMPLATECONF` value is no longer read. A wrong or missing path then still prints an error but does not change the build, which can hide the mistake.

---

## 11. Verify the configured layers

```bash
bitbake-layers show-layers
```

The minimal configuration should include:

```text
core
meta-poky
meta-yocto-bsp
meta-oe
meta-python
meta-multimedia
meta-arm-toolchain
meta-arm
meta-rz-bsp
meta-rz-distro
```

If you added the Graphics and Codec layers ([section 9.4](#94-optional-graphics-and-video-codec-layers)), `meta-rz-graphics` and `meta-rz-codecs` are listed as well.

---

## 12. Build the image

### 12.1 Set the environment

```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export BOARD=smarc-rzg2l
```

### 12.2 Limit parallelism on low-RAM hosts

Skip this section on hosts with 16 GB or more RAM.

By default BitBake runs one task thread and one `make` job per CPU core. Each C++ compile job or kernel `git` clone can use 1 GB or more, so a host with 8 GB RAM or less can run out of memory. The kernel then kills a process (for example `cc1plus` during `boost`, or `git index-pack` during the kernel clone) and the build fails. See [section 16.6](#166-out-of-memory-oom-failures).

Use the table to choose values:

| Host RAM | `BB_NUMBER_THREADS` | `PARALLEL_MAKE` |
|---|---|---|
| 16 GB or more | default | default |
| 8 to 16 GB | `"4"` | `"-j 4"` |
| Less than 8 GB (for example 7.6 GB) | `"3"` | `"-j 3"` |

Add them to `build/conf/local.conf` after initializing the build environment (section 10), for example:

```bash
cd "${WORK}/build"
cat >> conf/local.conf <<'EOF'

# Limit parallelism on low-RAM hosts
BB_NUMBER_THREADS = "3"
PARALLEL_MAKE = "-j 3"
EOF
```

The build is slower but completes. Optionally add swap as extra protection:

```bash
sudo fallocate -l 8G /swapfile2
sudo chmod 600 /swapfile2
sudo mkswap /swapfile2
sudo swapon /swapfile2
free -h
```

This swap does not persist after a reboot unless it is added to `/etc/fstab`. On WSL2, raise `memory` and `swap` in `.wslconfig` instead ([section 3.3.6](#336-set-resource-limits)).

### 12.3 Run BitBake

On a host with less than 16 GB RAM, apply section 12.2 first and fetch the kernel source on its own (see [section 16.6](#166-out-of-memory-oom-failures)):

```bash
MACHINE=${BOARD} bitbake linux-renesas -c fetch
```

Then build:

```bash
MACHINE=${BOARD} bitbake core-image-minimal
```

Equivalent:

```bash
MACHINE=smarc-rzg2l bitbake core-image-minimal
```

The first build takes hours and downloads many GB. Later builds reuse the sstate cache. Optionally build an SDK toolchain with `MACHINE=${BOARD} bitbake core-image-minimal -c populate_sdk`; the output goes to `$WORK/build/tmp/deploy/sdk/`.

### 12.4 Verify the configuration summary

Expected values include:

```text
BB_VERSION           = "2.8.0"
TARGET_SYS           = "aarch64-poky-linux"
MACHINE              = "smarc-rzg2l"
DISTRO               = "rz-bsp-plus"
DISTRO_VERSION       = "5.0.11"
TUNE_FEATURES        = "aarch64 crypto cortexa55"
```

---

## 13. Confirm that the build succeeded

A successful build returns to the prompt and reports that all tasks succeeded.

Check whether BitBake is still running:

```bash
ps -ef | grep '[b]itbake'
```

Verify the image directory:

```bash
ls -lh "$WORK/build/tmp/deploy/images/smarc-rzg2l/"
```

### 13.1 Observed non-fatal warnings

The successful builds included warnings about:

- The unvalidated `linuxmint-22.3` host distribution
- `perf` files that could not be changed with `chown/chmod` and returned `Errno 22`
- No LTTng modules because `CONFIG_TRACEPOINTS` might not be enabled (`lttng-modules: no modules were created`)
- On an Ubuntu 20.04 host: one warning in total

The final task summary reported success and the expected deploy artifacts were generated.

---

## 14. Locate the generated artifacts

Output directory:

```text
$WORK/build/tmp/deploy/images/smarc-rzg2l/
```

### 14.1 Complete microSD image

```text
core-image-minimal-smarc-rzg2l.rootfs.wic.gz
core-image-minimal-smarc-rzg2l.rootfs.wic.bmap
```

Timestamped names have this form:

```text
core-image-minimal-smarc-rzg2l.rootfs-<build-timestamp>.wic.gz
core-image-minimal-smarc-rzg2l.rootfs-<build-timestamp>.wic.bmap
```

### 14.2 Other output formats

```text
core-image-minimal-smarc-rzg2l.rootfs.ext4
core-image-minimal-smarc-rzg2l.rootfs.tar.bz2
core-image-minimal-smarc-rzg2l.rootfs.tar.gz
Image
Image-smarc-rzg2l.bin
modules-smarc-rzg2l.tgz
r9a07g044l2-smarc.dtb
bl2.bin
bl31.bin
fip.bin
u-boot.bin
```

Use the `.wic.gz` and `.wic.bmap` files for the complete microSD image. The `.ext4` file alone is only the root filesystem.

### 14.3 Copy the image to Windows (WSL2)

Only needed when the card is written from Windows ([section 17.9](#179-write-the-image-from-windows)).

Windows can read the WSL filesystem at:

```text
\\wsl$\<distro-name>\home\<user>\RZG2L\build\tmp\deploy\images\smarc-rzg2l\
```

Or copy the files from inside WSL:

```bash
cp "$WORK"/build/tmp/deploy/images/${BOARD}/core-image-minimal-smarc-rzg2l.rootfs.wic.{gz,bmap} \
  /mnt/c/Users/<your-user>/Downloads/
```

---

## 15. Resume or repeat the build

Do not delete `tmp/` after an interruption. Reinitialize the environment and rerun the target:

```bash
export WORK=~/RZG2L   # use the directory chosen in section 7
cd "$WORK"

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export BOARD=smarc-rzg2l

# Ubuntu 24.04 with buildtools only (section 10.1)
. "$WORK/buildtools/environment-setup-x86_64-pokysdk-linux"

TEMPLATECONF=${PWD}/meta-renesas/meta-rz-distro/conf/templates/rz-bsp-plus-conf \
source poky/oe-init-build-env build

MACHINE=${BOARD} bitbake core-image-minimal
```

BitBake reuses successfully completed tasks.

---

## 16. Build logs and troubleshooting

### 16.1 BitBake server log

```bash
cd "$WORK/build"
tail -100 bitbake-cookerdaemon.log
tail -f bitbake-cookerdaemon.log
grep -i "error" bitbake-cookerdaemon.log | tail -50
```

### 16.2 Find recent task logs

```bash
find tmp/work -type f -name "log.do_*" -printf '%T@ %p\n' \
  | sort -nr \
  | head -20
```

### 16.3 Search task logs for errors

```bash
grep -R "^ERROR:" tmp/work/*/*/*/temp/log.do_* 2>/dev/null | tail -50
```

### 16.4 Inspect a task log

```bash
tail -100 tmp/work/<architecture>/<recipe>/<version>/temp/log.do_<task>.*
```

### 16.5 Hash-server socket interruption

If a task reports a local hash-server Unix-socket `FileNotFoundError`, reinitialize the build environment and rerun the same BitBake command. Do not delete the entire `tmp/` directory first.

### 16.6 Out-of-memory (OOM) failures

A host with little RAM (8 GB or less) can fail with the kernel OOM killer. It is not caused by the network or the repositories. Two failures were observed on a 7.6 GB host:

| Failing task | Symptom |
|---|---|
| `linux-renesas do_fetch` | `fatal: index-pack failed` while cloning `rz_linux-cip.git` (about 11.5 M objects) |
| `boost do_compile` | `g++: fatal error: Killed signal terminated program cc1plus` |

Confirm the cause:

```bash
sudo dmesg | grep -iE "out of memory|killed process" | tail
free -m
```

Fix:

1. Apply [section 12.2](#122-limit-parallelism-on-low-ram-hosts).
2. Fetch the kernel source alone while the host is otherwise idle:
   ```bash
   MACHINE=${BOARD} bitbake linux-renesas -c fetch
   ```
3. Re-run `MACHINE=${BOARD} bitbake core-image-minimal`. Completed tasks are reused, so the build continues near the failed task.

Monitor progress from another shell, with the build log saved by `tee` (see [section 3.4](#34-keep-the-build-running-after-disconnecting)):

```bash
grep -o "Running task [0-9]* of [0-9]*" ~/rz_build.log | tail -1
grep "^ERROR" ~/rz_build.log | tail
```

### 16.7 Ubuntu 24.04 pseudo and tar errors

On some Ubuntu 24.04 hosts, BitBake fails in `do_package` tasks. The first failing recipe was `linux-libc-headers`, then `base-files`, `tzdata` and `ca-certificates`:

```text
got *at() syscall for unknown directory, fd 4
unknown base path for fd 4, path include
couldn't allocate absolute path for 'include'.
tar: ./usr/include/drm: Cannot mkdir: No such file or directory
ERROR: Task (...linux-libc-headers_6.6.bb:do_package) failed with exit code '1'
```

Ubuntu 22.04 and 20.04 do not have this problem, so the simplest fix is to use one of them. Otherwise recover as follows:

1. Install and activate buildtools ([section 10.1](#101-ubuntu-2404-only-install-and-activate-buildtools)).
2. Remove the stale host-tool links. BitBake caches them in `build/tmp/hosttools/`, and if they were created before buildtools was active, `tar` still points to `/usr/bin/tar`:

   ```bash
   ls -l "$WORK/build/tmp/hosttools/tar"     # bad if it shows -> /usr/bin/tar
   rm -rf "$WORK/build/tmp/hosttools"
   ```

3. Initialize the build environment again ([section 10.3](#103-initialize-the-build-directory)), clean the failed recipes, and rebuild:

   ```bash
   bitbake -c cleansstate base-files tzdata ca-certificates linux-libc-headers
   MACHINE=${BOARD} bitbake core-image-minimal
   ```

### 16.8 Other common problems

| Problem | Cause and fix |
|---|---|
| BitBake complains about the locale | Generate and export `en_US.UTF-8` ([section 5](#5-configure-the-utf-8-locale)). `C` and `POSIX` are not enough. |
| `bitbake-layers: command not found` | It was run before `oe-init-build-env`. Initialize the build environment first. |
| `TEMPLATECONF ... nonexistent directory` | Wrong template name. Use `find meta-renesas -type d \| grep templates`; for this tag it is `rz-bsp-plus-conf` ([section 10.2](#102-verify-the-template-path)). |
| Buildtools installed but the same `pseudo` error | Stale `build/tmp/hosttools/tar -> /usr/bin/tar`. See [section 16.7](#167-ubuntu-2404-pseudo-and-tar-errors). |
| Forgot buildtools in a new shell (Ubuntu 24.04) | Source `buildtools/environment-setup-x86_64-pokysdk-linux` before `oe-init-build-env`. |
| Duplicate layer or `local.conf` lines | Add layers and `IMAGE_INSTALL` lines only once. Check with `bitbake-layers show-layers` and `tail conf/local.conf`. |
| Out of disk space | The build needs about 110 GB or more. Check `df -h ~`. On WSL2 the virtual disk lives on the Windows drive, so free space there. |
| Download failures | Run the same `bitbake` command again. Check the network, VPN or proxy settings. |
| Build very slow | Build in the Linux filesystem (not `/mnt/c`) and give the host or WSL more RAM and CPU. |
| WSL: `wsl --install` is not recognized or fails | Update Windows, enable virtualization in BIOS/UEFI, and run PowerShell as Administrator. |
| WSL: distribution shows `VERSION 1` | Run `wsl --set-version <distro-name> 2`. |
| WSL: out-of-memory failure during the build | Raise `memory` and `swap` in `.wslconfig`, run `wsl --shutdown`, and apply [section 12.2](#122-limit-parallelism-on-low-ram-hosts). |
| WSL: build slow or files have wrong permissions | The workspace is under `/mnt/c`. Move it to the Linux home directory. |
| WSL: card reader not visible | Use Balena Etcher on Windows ([section 17.9](#179-write-the-image-from-windows)). |

---

## 17. Write the image to a microSD card

This procedure applies to both a new blank card and a previously used card. A new card does not need to be formatted or partitioned first because the `.wic.gz` image contains the partition layout and filesystems.

Choose the method that matches where the card reader is connected:

| Card reader connected to | Use |
|---|---|
| A Linux host (sections 17.1 to 17.8) | `bmaptool` (or `dd` as fallback) |
| A Windows PC (including a WSL2 build) | [Section 17.9](#179-write-the-image-from-windows) |

> **Warning:** This operation is destructive. Writing to the wrong device can overwrite the host disk.

### 17.1 Confirm the required files

```bash
cd "$WORK/build/tmp/deploy/images/smarc-rzg2l"

ls -lh \
  core-image-minimal-smarc-rzg2l.rootfs.wic.gz \
  core-image-minimal-smarc-rzg2l.rootfs.wic.bmap
```

Optionally test the compressed image:

```bash
gzip -t core-image-minimal-smarc-rzg2l.rootfs.wic.gz
```

No output means the gzip integrity check passed.

### 17.2 Identify the microSD device

Before inserting the card:

```bash
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,TRAN
```

Insert the microSD card and run the same command again:

```bash
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,TRAN
```

Identify the newly added disk by its size and model. A nominal 32 GB card often appears as approximately 29 to 30 GiB.

Example only:

```text
sdb      /dev/sdb   29.7G disk                         USB SD Reader usb
├─sdb1   /dev/sdb1   100M part vfat  /media/...
└─sdb2   /dev/sdb2   391M part ext4
```

The destination is the **whole card**, such as `/dev/sdb`, not a partition such as `/dev/sdb1`.

After positively identifying it, set:

```bash
export SD_DEVICE=/dev/sdX
```

Replace `/dev/sdX` with the actual whole-card device and verify:

```bash
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,TRAN "$SD_DEVICE"
```

### 17.3 Unmount card partitions

```bash
lsblk -lnpo NAME,MOUNTPOINTS "$SD_DEVICE" \
  | awk '$2 != "" {print $1}' \
  | xargs -r sudo umount
```

Confirm that no card partition has a mount point:

```bash
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$SD_DEVICE"
```

### 17.4 Write with bmaptool

```bash
sudo bmaptool copy \
  --bmap core-image-minimal-smarc-rzg2l.rootfs.wic.bmap \
  core-image-minimal-smarc-rzg2l.rootfs.wic.gz \
  "$SD_DEVICE"
```

Example only, if the card was verified as `/dev/sdb`:

```bash
sudo bmaptool copy \
  --bmap core-image-minimal-smarc-rzg2l.rootfs.wic.bmap \
  core-image-minimal-smarc-rzg2l.rootfs.wic.gz \
  /dev/sdb
```

Never use `/dev/sdb1` or another partition as the destination.

### 17.5 Flush and verify

```bash
sync
sudo partprobe "$SD_DEVICE" 2>/dev/null || true
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL "$SD_DEVICE"
```

The card should now show the partition layout created by the WIC image.

If the desktop mounts a partition automatically after writing, unmount it:

```bash
lsblk -lnpo NAME,MOUNTPOINTS "$SD_DEVICE" \
  | awk '$2 != "" {print $1}' \
  | xargs -r sudo umount

sync
```

### 17.6 Safely remove the card

If available:

```bash
udisksctl power-off -b "$SD_DEVICE"
```

After the device powers off, remove the card and insert it into the RZ/G2L board.

### 17.7 Fallback method with dd

Use this only if `bmaptool` is unavailable:

```bash
gzip -dc core-image-minimal-smarc-rzg2l.rootfs.wic.gz \
  | sudo dd of="$SD_DEVICE" bs=4M status=progress conv=fsync

sync
```

### 17.8 Troubleshooting

#### Device is busy

Check for mounted partitions and unmount them:

```bash
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$SD_DEVICE"
```

#### Permission denied

Use `sudo` for the write operation. Do not change block-device permissions.

#### Card does not appear

Reconnect the reader and check:

```bash
sudo dmesg | tail -50
```

On a Windows PC with WSL2, a USB card reader is not visible in WSL by default. Use [section 17.9](#179-write-the-image-from-windows).

#### Unallocated space remains on a 32 GB card

This is expected when the WIC image is smaller than the card. Do not resize partitions until the board has booted successfully from the original image.

### 17.9 Write the image from Windows

Use this when the build was done on WSL2, or when the card reader is on a Windows PC. First copy the image to Windows ([section 14.3](#143-copy-the-image-to-windows-wsl2)).

> **Warning:** Writing an image erases the whole card. Check the target drive carefully before you write.

#### Method A (simplest): Balena Etcher

1. Install [Balena Etcher](https://etcher.balena.io/).
2. Click **Flash from file** and select `core-image-minimal-smarc-rzg2l.rootfs.wic.gz`. Etcher reads `.gz` directly.
3. Click **Select target** and choose the microSD card. Check the size to make sure it is the right device.
4. Click **Flash!** and wait for validation to finish.

#### Method B: Rufus or Win32 Disk Imager

These tools need a raw `.wic` file, not `.gz`. Extract it first (with 7-Zip on Windows, or in WSL):

```bash
gunzip -k core-image-minimal-smarc-rzg2l.rootfs.wic.gz
```

Then write the `.wic` file with Rufus (select **DD Image** mode if asked) or Win32 Disk Imager.

#### Method C: bmaptool inside WSL with usbipd-win

WSL2 cannot see USB devices by default. Attach the card reader with `usbipd-win`.

In **PowerShell as Administrator**:

```powershell
winget install --interactive --exact dorssel.usbipd-win
usbipd list
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID>
```

In WSL, identify the card by its size and make sure it is not the WSL disk ([section 17.2](#172-identify-the-microsd-device)):

```bash
lsblk
```

Then write it, replacing `/dev/sdX` with the whole-card device:

```bash
sudo umount /dev/sdX* 2>/dev/null
cd "$WORK/build/tmp/deploy/images/${BOARD}/"
sudo bmaptool copy core-image-minimal-smarc-rzg2l.rootfs.wic.gz /dev/sdX
sync
```

Detach the reader when done (PowerShell): `usbipd detach --busid <BUSID>`. If the reader does not show up in WSL, use Method A.

After writing, eject the card from Windows before pulling it out.

---

## 18. Boot the board

1. Power off the EVK and insert the microSD card into the SD slot.
2. Set the boot-mode DIP switches for **SD card boot**. The positions depend on the board revision, so follow the Renesas *Getting Started* page: <https://renesas-rz.github.io/rz_linux_bsp_plus/RZG/getting_started/>
3. Connect a USB cable from the EVK serial (debug) port to the PC.
4. Open a serial terminal (Tera Term, PuTTY, or `minicom`) with **115200 baud, 8 data bits, no parity, 1 stop bit, no flow control**.
5. Power on the board. U-Boot and then Linux messages should appear.
6. Log in as `root` (the default image has no password).

If the board does not boot from the card, re-check the boot-mode switches against the board manual, and confirm that the write finished and verified.

---

## Appendix A: Condensed command sequence

The minimal sequence that produced a working build, for a native Linux host, a remote host, or the Ubuntu shell inside WSL2. Skip the buildtools lines on Ubuntu 22.04 and 20.04, and skip the Graphics and Codec lines for the minimal image. On hosts with less than 16 GB RAM, add the `local.conf` limits from [section 12.2](#122-limit-parallelism-on-low-ram-hosts).

```bash
# --- packages, locale, git ---
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential chrpath cpio debianutils diffstat file gawk gcc git \
  iputils-ping libacl1 liblz4-tool locales python3 python3-git python3-jinja2 \
  python3-pexpect python3-pip python3-subunit socat texinfo unzip wget xz-utils zstd bmap-tools
sudo locale-gen en_US.UTF-8 && sudo update-locale LANG=en_US.UTF-8
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
git config --global user.email "<email>" && git config --global user.name "<name>"

# --- sources ---
export WORK=~/RZG2L BOARD=smarc-rzg2l
mkdir -p $WORK && cd $WORK
git clone https://git.yoctoproject.org/git/poky
git -C poky checkout -b tmp ae2d52758fc2fcb0ed996aa234430464ebf4b310
git clone https://git.yoctoproject.org/meta-arm
git -C meta-arm checkout -b tmp 8e0f8af90fefb03f08cd2228cde7a89902a6b37c
git clone https://git.openembedded.org/meta-openembedded
git -C meta-openembedded checkout -b tmp c29a18fa39ede952f3f6108ec007c1906e2d9a0d
git clone https://github.com/renesas-rz/meta-renesas
git -C meta-renesas checkout -b tmp BSP-PLUS-K6.12-V2.0

# --- optional Graphics + Codec (zip files copied into $WORK first) ---
unzip RTK0EF0045Z14001ZJ-*.zip
tar zxvf RTK0EF0045Z14001ZJ-*/meta-rz-features_graphics_*.tar.gz
unzip RTK0EF0045Z16002ZJ_*.zip
tar zxvf RTK0EF0045Z16002ZJ_*/meta-rz-features_codec_*.tar.gz

# --- Ubuntu 24.04 only: buildtools ---
wget https://downloads.yoctoproject.org/releases/yocto/yocto-5.0.11/buildtools/x86_64-buildtools-extended-nativesdk-standalone-5.0.11.sh
chmod +x x86_64-buildtools-extended-nativesdk-standalone-5.0.11.sh
./x86_64-buildtools-extended-nativesdk-standalone-5.0.11.sh -y -d $WORK/buildtools
. $WORK/buildtools/environment-setup-x86_64-pokysdk-linux
which tar                          # must be under $WORK/buildtools
rm -rf $WORK/build/tmp/hosttools   # only if an earlier build failed

# --- init, layers, build ---
cd $WORK
TEMPLATECONF=${PWD}/meta-renesas/meta-rz-distro/conf/templates/rz-bsp-plus-conf source poky/oe-init-build-env build
bitbake-layers add-layer ../meta-rz-features/meta-rz-graphics     # optional
bitbake-layers add-layer ../meta-rz-features/meta-rz-codecs       # optional
bitbake -c cleansstate base-files tzdata ca-certificates linux-libc-headers   # only after a failed build
MACHINE=${BOARD} bitbake core-image-minimal

# --- result ---
ls -lh $WORK/build/tmp/deploy/images/$BOARD/
```

Every new shell needs: the `LANG` and `LC_ALL` exports, `WORK` and `BOARD`, then (Ubuntu 24.04) the buildtools script, then `oe-init-build-env`.

---

## Appendix B: Docker experiment and limitation

Docker was tested but was not used for the successful build.

### B.1 Install Docker

```bash
sudo apt update
sudo apt install -y docker.io
sudo usermod -aG docker "$USER"
newgrp docker
docker --version
```

### B.2 Tested container

```bash
docker run -it \
  -v "$WORK":/work \
  --name yocto-build \
  crops/poky:latest
```

The tested container provided Python 3.6.9, but BitBake required Python 3.8 or newer. The successful build was therefore performed directly on the Linux host with Python 3.12.3.

Remove the unused container if required:

```bash
docker stop yocto-build 2>/dev/null || true
docker rm yocto-build
```
