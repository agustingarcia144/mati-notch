<div align="center">

<img src="mati-notch/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="96" alt="mati-notch icon">

# mati-notch

**A tiny friend that lives in your Mac's notch — or at the top of your screen on Windows and Linux — and keeps an eye on your AI coding agent sessions.**

Approve permissions, watch your agents work, drop a file, chat with Claude — all without leaving what you're doing.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-AppImage%20%7C%20deb%20%7C%20rpm-FCC624?logo=linux&logoColor=black)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-native-0A84FF)
![Tauri 2](https://img.shields.io/badge/Tauri-2-FFC131?logo=tauri&logoColor=black)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![GitHub stars](https://img.shields.io/github/stars/agustingarcia144/mati-notch?style=social)

<img src="docs/media/demo.gif" width="760" alt="mati-notch in action">

</div>

---

## Why

Some studios showed off gorgeous notch companions… and never let anyone use them.
**mati-notch is the open version.** Every line of code, every animation, every sound — free to use, read, fork and remix.

Meet **mati-notch**: a soft little squircle with big eyes that pops out of your notch, waves hello, follows your cursor with its eyes, gets annoyed when you poke it (and dizzy if you insist), and tells you the moment Claude Code needs you.

## Features

- 🤖 **Claude Code, Cursor, Codex, Gemini CLI, Antigravity and other agents, live** — see every session in your notch: what it reads, edits and runs, step by step. Tag a hook payload with `mati_notch_agent` to give any agent its own pill (see [`docs/AGENTS.md`](docs/AGENTS.md)). Finished? mati-notch does a happy little jump.
- ✅ **Approve and answer from the notch** — Claude Code permission requests show up with **Allow / Deny / Always**; `AskUserQuestion` prompts show the choices right in the notch (single or multi-select, up to 4 questions). One click, or "Reply in terminal" to fall back to the CLI. Codex also gets Allow / Deny.
- 🧑‍💻 **Jump to the right terminal** — open the exact terminal window of a session *(macOS)*.
- 💬 **Chat with Claude Code or Codex using your subscription** — choose either CLI provider in the chat picker. mati-notch uses your local CLI sign-in and rejects API-key authentication for these options. Anthropic API, Google AI, OpenAI API, and local models remain separate choices. *(CLI chat: direct-download macOS build, Windows and Linux; Google AI, OpenAI API and local models: macOS)*
- 📊 **Claude plan usage** *(macOS, GitHub build)* — a small pill in the notch header shows your 5-hour and weekly Claude plan limits. Enable it from Settings → Agents → Plan usage. Pro and Max plans only.
- 📋 **Declare the tools you use** — open Settings → Active pills and pick your main workspace tool (VS Code, Cursor, Codex or Antigravity), then toggle up to 4 more: Gemini CLI, Anthropic, Google AI, OpenAI, Ollama, LM Studio and service integrations *(macOS)*.
- 📎 **Drop a file on the notch** — mati-notch turns into a box and swallows it, then ask a question about it or send it by email *(email: macOS, Mail.app)*.
- 🪟 **Drag mati-notch onto any window** — attach that window as context for Claude *(macOS)*.
- 🔌 **Integrations** — Stripe payments, n8n workflows, GitHub, Vercel deployments, Resend emails, Notion, Cal.com, and Convex projects and resource usage (macOS). Each one gets its own little colored mati-notch.
- 🎵 **Apple Music pill** *(macOS, GitHub build)* — add the Apple Music pill in Settings → Active pills to see what's playing and control playback from the notch; mati-notch dances while it plays.
- 🎭 **A real character** — idle breathing, blinks, eyes on a sphere that follow your mouse, emotes, 28 handcrafted sounds, a greeting on launch.
- 🫥 **Invisible when idle** — hides away when nothing is running, peeks out when you hover the notch (the top edge of the screen on Windows and Linux).
- 🖥️ **Any Mac, notch or not** — on an iMac, a Mac mini, or a MacBook with its lid closed on an external display, mati-notch sits in a small bar at the top of the screen.
- 🔒 **Private by design** — no telemetry, no account. Keys live in your macOS Keychain, Windows Credential Manager or Linux Secret Service (GNOME Keyring, KWallet). The app only talks to the services you plug in.

<table>
<tr>
<td><img src="docs/media/claude-code.png" alt="Claude Code session"></td>
<td><img src="docs/media/stripe.png" alt="Stripe payments"></td>
</tr>
<tr>
<td><img src="docs/media/chat.png" alt="Chat with Claude"></td>
<td><img src="docs/media/dizzy.png" alt="Too many hits"></td>
</tr>
</table>

## Install

### Download for macOS

1. Grab the latest `mati-notch.zip` from [Releases](https://github.com/agustingarcia144/mati-notch/releases).
2. Unzip and move **mati-notch.app** to `/Applications`.
3. Launch it, and click **Open** when macOS asks you to confirm. Updating from 0.1.0? macOS may ask you, once for each key you saved, to let mati-notch use it: enter your Mac password and click **Always Allow**.

### Windows

The Windows installer is **temporarily unavailable**. Microsoft Defender wrongly
flags the unsigned installer as malware; a false-positive report is under review
at Microsoft and the installer will come back once it is cleared and signed.
Until then you can [build it from source](#build-from-source).

There is no notch on a PC, so the island slides out of the top edge of the screen
instead of hiding inside one. See [`windows/README.md`](windows/README.md) for the
rest of the differences.

### Linux

The first Linux build is out as a beta: download it from [mati-notch for Linux 0.1.1 (beta)](https://github.com/agustingarcia144/mati-notch/releases/tag/linux-v0.1.1), x86_64 only for now. Later versions will be in [Releases](https://github.com/agustingarcia144/mati-notch/releases) under `linux-v*` tags.

- **AppImage** (any distribution): `chmod +x mati-notch-Linux-*.AppImage`, then run it.
- **Debian / Ubuntu**: `sudo apt install ./mati-notch-Linux-*.deb`
- **Fedora / openSUSE**: `sudo dnf install ./mati-notch-Linux-*.rpm`

Check a download with `sha256sum -c SHA256SUMS --ignore-missing`. Gemini CLI, Antigravity, Google AI, OpenAI and local model (Ollama / LM Studio) chat are macOS only for now.

The island sits on the top edge on compositors with layer-shell — COSMIC, KDE
Plasma, Hyprland, Sway and other wlroots compositors. GNOME has no layer-shell,
so there it opens as a regular window. See [`windows/README.md`](windows/README.md#linux).

### Build from source

**macOS** — requirements: macOS 15+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/agustingarcia144/mati-notch.git
cd mati-notch/mati-notch
xcodegen
open mati-notch.xcodeproj   # then ⌘R
```

**Windows** — requirements: [Rust](https://rustup.rs), Node 20+, MSVC build tools.

```powershell
git clone https://github.com/agustingarcia144/mati-notch.git
cd mati-notch/windows
npm install
npm run pack                # installer lands in windows/release/
```

**Linux** — requirements: [Rust](https://rustup.rs), Node 20+, and the WebKitGTK,
gtk-layer-shell and appindicator development packages (Debian/Ubuntu names below).

```bash
sudo apt install build-essential pkg-config \
  libwebkit2gtk-4.1-dev libgtk-layer-shell-dev libayatana-appindicator3-dev \
  librsvg2-dev libssl-dev libdbus-1-dev patchelf \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good
git clone https://github.com/agustingarcia144/mati-notch.git
cd mati-notch/windows
npm install
npm run pack                # AppImage, .deb and .rpm land in windows/release/
```

## Setup

Click the mati-notch icon in the menu bar (macOS) or in the system tray (Windows, Linux) → **Settings…**

| What | Why | Where the key goes |
|---|---|---|
| **Claude Code hooks** | live sessions and approvals | **Install hooks** — mati-notch backs up `~/.claude/settings.json`, merges its hooks and shows you the diff before writing anything |
| **Claude plan** *(macOS, GitHub build)* | Plan usage gauge in the notch header | **Install relay** in Settings → Agents → Plan usage, then enable "Show in the notch" |
| **Gemini CLI hooks** *(macOS)* | Gemini CLI sessions in the island | **Install hooks** in Settings → Gemini CLI — backs up `~/.gemini/settings.json` |
| **Antigravity (agy) hooks** *(macOS)* | agy sessions in the island | **Install hooks** in Settings → Antigravity — backs up `~/.gemini/config/hooks.json` |
| **Claude Code subscription chat** | built-in chat through your local CLI | Run `claude auth login`, then choose **Claude Code** in the chat picker or Settings → Chat |
| **Codex subscription chat** | built-in chat through your local CLI | Run `codex login` with ChatGPT, then choose **Codex** in the chat picker or Settings → Chat |
| **Anthropic API key** | chat and questions about files | Settings → Anthropic API · Keychain / Windows Credential Manager / Secret Service |
| **Google AI API key** *(macOS)* | chat with Google AI (Gemini) | Settings → Chat — other providers · Keychain |
| **OpenAI API key** *(macOS)* | chat with OpenAI | Settings → Chat — other providers · Keychain |
| **Ollama server** *(macOS)* | chat with local models via Ollama | Settings → Chat → Local models → **Connect** |
| **LM Studio server** *(macOS)* | chat with local models via LM Studio | Settings → Chat → Local models → **Connect** |
| **Active pills** *(macOS)* | choose which tools and agents appear in the island | Settings → Active pills |
| Convex *(macOS)* | Project list and current billing-period resource usage | Settings → Integrations → Convex: team access token in Keychain, numeric team ID in preferences; then enable in Active pills |
| Stripe, n8n, GitHub, Vercel, Resend, Notion, Cal.com | the service pills | Keychain / Windows Credential Manager / Secret Service, all optional |

If mati-notch isn't running, the hook exits immediately: **Claude Code is never blocked.**

### Convex setup (macOS)

Create a **team access token** in your [Convex dashboard](https://dashboard.convex.dev) and copy the associated numeric team ID. A deployment key or project-scoped token will not work. In Settings → Integrations → Convex, enter both and click **Save & validate**. Enable Convex in **Active pills** (up to four extra pills). Leaving the token blank and saving disconnects it.

The pill lists all projects by default; use the Projects selector in Settings to narrow the list. Open a project to view function calls, database storage, file storage, and data egress for the current billing period, across its deployments. Refresh manually or leave the card open for ten-minute refreshes. Closing it stops polling. Project IDs preserve selections when names change.

Project discovery uses the public Management API. Resource usage uses an **undocumented dashboard API** and may be unavailable with team tokens or after Convex changes that API. In that case projects remain available and **Open in Convex** takes you to the dashboard. Missing metrics display as unavailable; previous values are marked stale after refresh failures. No browser cookies, custom analytics, plan percentages, or estimated costs are collected or calculated.

### Subscription chat setup

Install the Claude Code and/or Codex CLI and sign in from Terminal (`claude auth login` or `codex login`). Choose **Claude Code** or **Codex** in the chat provider picker. The CLI uses your subscription account and its normal limits; mati-notch never reads or stores its OAuth tokens. API-key sign-in is rejected for these two providers, with no automatic API fallback.

Settings → Chat lets you set an executable path when automatic detection cannot find the CLI, and a model ID or `default`. Conversation context and up to 96 KB of an attached UTF-8 text file are sent through stdin. CLI chat runs in a separate temporary directory, disables hooks and shell tools, and supports stopping or timing out a request. The macOS App Store build does not offer CLI chat because its sandbox cannot run external CLIs.

## Things to try

| Do this | mati-notch does that |
|---|---|
| Hover the notch (top edge on Windows and Linux) | peeks out and says hi 👋 |
| Click it | opens |
| Hover mati-notch | blinks, eyes grow |
| Click mati-notch | squish + annoyed |
| Click 3 times fast | 😵‍💫 dizzy for a few seconds |
| Drag a file onto the island | turns into a box and swallows it |
| Drag mati-notch onto a window *(macOS)* | attaches it as context |
| Click the model name above the chat box *(macOS)* | switch AI provider or model |

## How it works

**macOS**

- **Island**: a borderless `NSPanel` hugging the notch, driven by a small state machine (`hidden → petit → home`).
- **Character**: drawn in SwiftUI `Canvas` + `TimelineView` at 60 fps — squircle body, eyes projected on a sphere, spring animations. No Rive, no Lottie, no images.
- **Claude Code**: a tiny `mati-notch-hook` script receives hook events and forwards them over a Unix socket to the app. For approvals it waits for your click, then answers the hook.
- **Integrations**: lightweight pollers, paused when nothing is watching.
- **Declared pills**: `PillCatalog.swift` is the single source of truth — every pill (coding tools, agents, AI providers, services) is declared there with its ID, color and category.
- **Sounds**: 28 short WAVs played through preloaded `AVAudioPlayer`s.

The macOS app is native Swift 6 / SwiftUI / AppKit with **zero third-party dependencies**.

**Windows**

- A [Tauri 2](https://tauri.app) app (Rust + TypeScript): the island is a transparent, always-on-top window that never steals focus, mati-notch is drawn in Canvas 2D with the same shapes, timings and sounds as on the Mac.
- Claude Code hooks go through a tiny `mati-notch-hook.exe` and a named pipe; keys live in Windows Credential Manager.
- Details and differences in [`windows/README.md`](windows/README.md).

**Linux**

- The same Tauri app as Windows. On Wayland the island is a gtk-layer-shell
  overlay anchored to the top edge, and click-through is its input region.
- Claude Code hooks go through the same `mati-notch-hook`, over a Unix socket in
  `$XDG_RUNTIME_DIR`; keys live in the Secret Service.

## Contributing

Issues and PRs are very welcome — new integrations, new emotes, new sounds, bug fixes. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

Built by [Louis Raillé](https://louisraille.fr) with Claude Code.
Inspired by the notch-companion concepts shared by design studios — this project is independent and not affiliated with any of them.

## License

- **Code:** [MIT](LICENSE) — use it, fork it, learn from it, just keep the copyright notice.
- **Name, mati-notch character, icon, sounds and media:** © Louis Raillé, all rights reserved — see [LICENSE-ASSETS.md](LICENSE-ASSETS.md). Shipping your own fork? Give it your own name and character.

<div align="center">

**If mati-notch made you smile, a ⭐ helps a lot.**

[Website](https://agustingarcia144.github.io/mati-notch/) · [Privacy](https://agustingarcia144.github.io/mati-notch/privacy.html) · [Terms](https://agustingarcia144.github.io/mati-notch/terms.html) · [Support](https://agustingarcia144.github.io/mati-notch/support.html)

</div>
