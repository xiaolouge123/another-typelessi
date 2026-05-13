# another-typelessi

another-typelessi is a macOS menu bar dictation app inspired by Typeless.

Press `Fn` to start recording, press it again to stop, and the app will:

1. Record local audio from the microphone.
2. Transcribe the audio. By default it streams to Deepgram (Nova-3) while you speak, so the transcript is ready almost as soon as you release `Fn`. You can switch to OpenRouter Whisper from Settings to upload the full WAV after recording instead.
3. Send the transcript to OpenRouter (`openai/gpt-5.4-mini` by default) for cleanup and formalization.
4. Paste the final text into the current cursor position, or copy it to the clipboard.

During recording and processing, a compact floating status indicator appears near the bottom center of the screen. It shows recording, transcribing, polishing, success, and error states.

Press `Esc` while recording or processing to cancel the current input. If transcription only returns silence, punctuation, or filler noise, the app treats that turn as empty input and does not paste or copy anything.

## Setup

Build, install, and open the app:

```sh
chmod +x scripts/build_app.sh
./scripts/build_app.sh
open /Applications/another-typelessi.app
```

Open the menu bar item and choose:

`Settings...`

From the settings window you can configure:

- Transcription provider: `Deepgram (streaming)` or `OpenRouter Whisper (batch)`
- Deepgram API key and model (defaults to `nova-3`)
- OpenRouter API key, base URL, and formalization model (used for GPT polish, plus the optional Whisper batch path)
- Output mode, transcription language, and clipboard behavior
- Weekly usage analysis split by stage/provider/model, with call counts, token counts, audio duration, and cost

Use `Auto Detect` for transcription language if you switch between Chinese and English. With Deepgram the app uses the `multi` language model, and with Whisper it omits the language hint. GPT polish is instructed to never translate the transcript.

Usage data is stored locally in `~/Library/Application Support/another-typelessi/usage.json`.

Settings are stored in the app's own JSON config file:

`~/Library/Application Support/another-typelessi/config.json`

The app does not read from macOS Keychain. Local config and usage files are written with owner-only permissions.

If you previously ran the app as `AnotherTypeless`, the first launch of this version migrates the old config and usage files into the `another-typelessi` application support directory.

## Permissions

The app asks for microphone permission when recording starts.

Fn hotkey monitoring uses macOS global key events, so Accessibility permission may also be needed for the hotkey to fire reliably.

For automatic paste into the current cursor, grant Accessibility permission:

`System Settings -> Privacy & Security -> Accessibility`

If Accessibility is not granted, `Paste at Cursor` silently falls back to copying the text to the clipboard.

If macOS keeps denying paste after you rebuild the app, reset the stale Accessibility record and add the rebuilt app again:

```sh
tccutil reset Accessibility com.local.another-typeless
```

The build script installs the app to `/Applications/another-typelessi.app`. Open that installed copy and enable it under Accessibility.

## Menu Options

- `Output -> Paste at Cursor`
- `Output -> Copy to Clipboard`
- `Transcription Language`
- `Formalize with GPT-5.4 Mini`
- `Restore clipboard after paste`

## Notes

This app does not use Siri or Apple Speech recognition. Speech recognition runs through Deepgram or OpenRouter Whisper depending on the configured provider; text formalization runs through OpenRouter using the OpenRouter API key.

## License

MIT
