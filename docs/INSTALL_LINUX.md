# Linux installation

Choose one installation method. Download links point to the [latest GitHub release](https://github.com/stevedat/VieLotus-IM/releases/latest).

## Automatic installer

The official installer detects the package manager and CPU architecture, installs the needed build/runtime packages, and selects a matching package or native build path:

```sh
curl -fsSL https://stevedat.github.io/VieLotus-IM/install.sh | sh
```

## Ubuntu: PPA

Use the PPA when your Ubuntu release and CPU architecture are listed on its [Launchpad page](https://launchpad.net/~stevedat/+archive/ubuntu/vielotus):

```sh
sudo add-apt-repository ppa:stevedat/vielotus
sudo apt update
sudo apt install vielotus
```

## Debian, Ubuntu, Mint: `.deb`

Download the matching `vielotus_<version>_<arch>.deb` from the latest release (`amd64` for x86_64, `arm64` for ARM64), then install it with APT. Replace the values below with the downloaded file's version and architecture:

```sh
version=2.0.3
arch=amd64 # use arm64 on ARM64
sudo apt install "./vielotus_${version}_${arch}.deb"
```

APT resolves package dependencies. The release page also provides `checksums.sha256` to verify the download.

## Arch Linux and Arch ARM

`CrossPlatform/packaging/arch/PKGBUILD` compiles the C++20 core, Fcitx5 addon, and IBus engine natively against the host Arch libraries (`PKGBUILD.bin` is also included for prebuilt `.deb` repackaging):

```sh
sudo pacman -S --needed base-devel cmake extra-cmake-modules git
# Plus one input-method framework:
sudo pacman -S --needed fcitx5-im  # Fcitx5, including GTK/Qt frontends (KDE/Hyprland/XFCE)
# or
sudo pacman -S --needed ibus       # IBus (GNOME)

git clone --depth 1 https://github.com/stevedat/VieLotus-IM.git
cd VieLotus-IM/CrossPlatform/packaging/arch
makepkg -si
vielotus-settings --activate
```

## First launch and input source

The package includes a first-login onboarding task. In a supported active desktop session, it refreshes the input-method registry and tries to add/activate Sen Việt. The automatic installer also adds Sen Việt to Ubuntu Language Selector's package choices on supported Ubuntu systems; installing a `.deb` directly does not make that Language Selector change.

On Ubuntu/GNOME, switch input methods with `Super` + `Space` and select **Sen Việt – Telex** (or VNI). On other desktops, use the desktop's configured shortcut and input-source settings. If Sen Việt is missing, run:

```sh
vielotus-settings --activate
```

Then check the desktop's keyboard/input-source settings. On Ubuntu/GNOME Wayland, log out and back in once if the new source is not shown or appears as `vielotus`. On Arch and other non-Debian desktops, there is no Ubuntu Language Selector entry; input-source presentation depends on the desktop and whether IBus or Fcitx5 is active.

For diagnostics, run `vielotus-settings --doctor`. See [Linux test status](TEST_STATUS.md) for CI and maintainer-reported manual results.
