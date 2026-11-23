# Contributing

Thanks for helping improve Easy Icon Arranger.

## Reporting a problem

Open an issue with:

- macOS version and Mac model
- iPhone model and iOS version
- What you did, what you expected and what happened
- If useful, the output of `go run ./cmd/probe` (read-only, it changes nothing on the phone)

Do not attach backup files publicly: they list every app installed on your phone.

## Development

```sh
go test ./...
go vet ./...
./scripts/build.sh --install
```

Guidelines:

- Keep the Go engine free of UI code and the Swift app free of device code. They talk only through the C API in `libeia`
- Any change to `internal/layout` needs a test. The round trip from raw state to model and back must stay lossless
- Never write to the phone in tests. `cmd/probe -write-same` exists for manual checks and always makes a backup first
- New interface strings go in `macos/Localization/en.json`. Other languages fall back to English until translated
- Use plain, short commit messages in English

## Translations

The interface is available in the 24 official languages of the European
Union. Each language is one JSON file in `macos/Localization/`, named by its
language code (`de.json`, `fr.json` and so on). English (`en.json`) is the
reference: a key missing from another file falls back to English.

Only English and Italian were written by a native speaker. The other files
are first drafts, so corrections from native speakers are very welcome.

To fix or add a language:

1. Edit or create `macos/Localization/<code>.json`, keeping every key and every `{0}`, `{1}` placeholder of the English text
2. Run `go test ./internal/l10ncheck/`: it checks the JSON, the keys and the placeholders
3. Build with `./scripts/build.sh`; new files are picked up automatically and macOS lists the language for the app

A language outside the EU list also works: add its code to `L10n.supported` in `macos/Sources/EasyIconArranger/L10n.swift`.

## Pull requests

1. Fork the repository and create a branch
2. Make your change with tests
3. Run `go test ./...` and build the app
4. Open the pull request with a short description and, for UI changes, a screenshot

By contributing you agree that your contribution is licensed under the MIT License.
