# Spokn

A macOS menu bar app for text-to-speech with a karaoke-style overlay.

## Features

- **Global Hotkey** - Press `Cmd+Shift+S` to read selected text from any application
- **Karaoke-style Overlay** - Words highlight as they're spoken
- **Multi-language Support** - Automatic detection for English and German
- **Playback Controls** - Play, pause, stop, restart, and adjustable speed (0.5x - 3.0x)
- **Content Type Detection** - Handles plain text, Markdown, HTML, and RTF

## Installation

1. Download the latest `Spokn-x.x.x.dmg` from [Releases](https://github.com/niklas-heer/spokn-tts/releases)
2. Open the DMG and drag Spokn to Applications
3. **First launch:** Right-click Spokn.app → Open → Click "Open" (required because the app isn't signed yet)

## Requirements

- macOS
- Accessibility permissions (for global hotkey and clipboard access)

## Usage

1. Select text in any application
2. Press `Cmd+Shift+S`
3. Spokn will read the text aloud with word highlighting

## Development

### Reset app state

```bash
defaults delete com.niklasheer.spokn hasLaunchedBefore
```

### Reset accessibility permissions

```bash
tccutil reset Accessibility com.niklasheer.spokn
```
