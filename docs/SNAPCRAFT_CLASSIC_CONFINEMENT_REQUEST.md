# Classic Confinement Request for `vielotus` — Sen Việt (VieLotusIM)

- **Forum Category:** `store-requests / classic-confinement` (`https://forum.snapcraft.io/c/store-requests/classic-confinement/26`)
- **Snap Name:** `vielotus` (`Snap ID: cB5CKJwC69Ne8qfQRJLyWsUnUqzEPzUl`)
- **Pending Classic Revisions:** `#38` (`amd64`, v2.0.2) & `#39` (`arm64`, v2.0.2)
- **Publisher Organization:** **Nido Holdings** (`SteveDat` / `@stevedat` / `ttd1232004`)

---

## Submitted Forum Post Body

To make the review of your request easier, please use the following template to provide all the required details and also include any other information that may be relevant.

---

* **name**: `vielotus`
* **description**: **Sen Việt (VieLotusIM)** is an open-source (MIT/Expat), memory-safe, 100% offline Vietnamese Input Method Engine (Telex & VNI with context-aware English–Vietnamese bilingual restoration) developed by **Nido Holdings** for Ubuntu Desktop and Linux distributions, supporting both **IBus** (`ibus-engine-vielotus`) and **Fcitx5** (`vielotus.so`), accompanied by a native GTK3 Settings & Diagnostics utility (`vielotus-settings`).
* **snapcraft**: https://github.com/stevedat/VieLotus-IM/blob/main/snap/snapcraft.yaml
* **upstream**: https://github.com/stevedat/VieLotus-IM
* **upstream-relation**: Official upstream creator, copyright holder, and verified multi-platform commercial publisher (**Nido Holdings** — Lead Architect: **Tran Phat Dat / Steve Dat**, GitHub `@stevedat`, Snap Store publisher `SteveDat` / `ttd1232004`, Snap ID `cB5CKJwC69Ne8qfQRJLyWsUnUqzEPzUl`).
  * **Publisher Vetting & Live Official Store Presence (Nido Holdings):**
    * **Apple App Store (iOS / iPadOS — Approved & Live):** `https://apps.apple.com/us/app/sen-vi%E1%BB%87t/id6821782799`
    * **Google Play Store (Android — Approved & Live):** `https://play.google.com/store/apps/details?id=org.vielotus.hardwarekeyboard`
    * **Microsoft Store (Windows TSF — Verified Publisher `Nido Holdings`, Seller ID `96917400`):** `https://apps.microsoft.com/detail/9PF5K64GXXSH`
    * **Ubuntu Launchpad PPA (GPG Key `9B5642F2EBA2A1EC`, same `ttd1232004@gmail.com` Ubuntu One identity):** `https://launchpad.net/~stevedat/+archive/ubuntu/vielotus`
* **supported-category**:
  1. *Local/non-root user-driven configuration/switching tools for desktop & development environments* (system-wide input method engine & switcher across terminals, IDEs, browsers, and GTK/Qt apps); and
  2. *Special exception for system integration features not yet supported by `snapd`*: `snapd` currently provides **client** input-method plugs (`desktop` / `desktop-legacy`), which permit sandboxed apps to *consume* an input method (`CreateInputContext`), but has **no `ibus-engine` or `fcitx5-addon` provider/slot interface** allowing a snap to register and serve as a host-level Input Method Engine for GNOME Shell / `ibus-daemon` / `fcitx5`.
* **reasoning**:
  We extensively built, published, and tested `vielotus` under `confinement: strict` (`core24`, revisions `#1` through `#37`) with `desktop`, `desktop-legacy`, `gsettings`, `home`, `wayland`, and `x11` plugs. Strict confinement fails completely for a Linux Input Method Engine due to four fundamental architectural boundaries in `snapd` / AppArmor:

  1. **Host `ibus-daemon` & GNOME Shell Engine Discovery (`/usr/share/ibus/component/`):**
     On Ubuntu Desktop (22.04 / 24.04 / 26.04 Wayland & X11), `org.freedesktop.IBus.session.GNOME.service` (`ibus-daemon`) discovers available input methods exclusively by scanning `/usr/share/ibus/component/*.xml` and compiling the system/session registry cache, while `gnome-shell` (`IBusManager`) resolves `org.gnome.desktop.input-sources` entries against `ibus-daemon`'s registered `IBusComponent` list. Under `strict` confinement, the snap cannot install its component descriptor (`/usr/share/ibus/component/vielotus-snap.xml`) nor invoke host `/usr/bin/ibus write-cache` / `ibus restart` to register `vielotus` with the live host `ibus-daemon`. (In our classic revisions `#38` amd64 and `#39` arm64, `meta/hooks/install` writes a dedicated `/usr/share/ibus/component/vielotus-snap.xml` guarded so it never overwrites any `dpkg`-managed file, and `meta/hooks/remove` removes it cleanly).
  2. **IBus Private D-Bus Socket & `org.freedesktop.IBus.Service` Provider Mediation:**
     Unlike normal desktop client apps, `ibus-engine-vielotus --ibus` is spawned *by* the host's `ibus-daemon` on demand and must connect back to the private user IBus D-Bus socket (`~/.config/ibus/bus/<machine-id>-unix-wayland-0`) to own bus names and export `org.freedesktop.IBus.Factory` / `org.freedesktop.IBus.Engine`. Strict confinement's `desktop-legacy` AppArmor profile only mediates *client* input context calls, blocking provider-side engine registration, and `home` blocks hidden dot-directories (`owner @{HOME}/[^.]**` denies `~/.config/ibus/bus/*`, `~/.cache/ibus/bus/*`, `~/.config/environment.d/*`, and `~/.local/lib/*`).
  3. **Fcitx5 In-Process Shared Library Addon (`dlopen`):**
     For KDE Plasma / Fcitx5 users, `fcitx5` loads input method engines in-process via `dlopen()` of `vielotus.so` (`FCITX_ADDON_DIRS`) linked against the host environment and reads user configuration under `~/.config/fcitx5/` and `~/.config/vielotus/`. Strict sandbox isolation prevents the host `fcitx5` daemon from loading the addon or sharing state cleanly without `classic` access.
  4. **Host Desktop Session Tooling & Fontconfig Integration:**
     `vielotus-settings` orchestrates live input-source switching and diagnostics across host `ibus`, `fcitx5-remote`, `gsettings`, `systemctl --user` (`org.freedesktop.IBus.session.GNOME.service`), and installs a non-conflicting `/etc/fonts/conf.d/51-vielotus-snap-vietnamese.conf` rule so Vietnamese combining/precomposed hook-above glyphs render without cell clipping in Ubuntu's GTK4 `gnome-text-editor` / VTE terminals.

  Classic revisions **`#38` (`amd64`)** and **`#39` (`arm64`)** (`v2.0.2`, `base: core24`, `confinement: classic`, passing all 26 automated store checks with 0 warnings) have already been uploaded to the Snap Store review queue (`https://dashboard.snapcraft.io/snaps/vielotus/revisions/38/`).

- [x] I understand that strict confinement is generally preferred over classic.
- [x] I’ve tried the [existing interfaces](https://snapcraft.io/docs/supported-interfaces) to make the snap to work under strict confinement.
