# Battery panel actions

The Battery settings page lets you choose what opens from the battery summary gear and the battery details button. Open **Settings → Battery → Battery action** and choose:

- **Battery Settings** to open macOS Battery settings.
- **AlDente** or **BatFi** when that app is installed.
- **Custom Application** to choose an `.app` bundle.
- **Custom URL** to enter any URL that parses and has a nonempty scheme.

For a custom application, Status Trio saves its display name, bundle identifier, and selected path. It uses the bundle identifier to find the app if it moves, then tries the saved path if the identifier no longer resolves. If the selected app is missing, its name stays selected and the settings page marks it as not installed. Reinstalling or relocating the app can make the saved choice available again.

Typing a custom URL does not open it. Empty or invalid input shows a nonmodal hint. When the battery action is used, an invalid URL, an unavailable app, or a failed open falls back to macOS Battery Settings.

Status Trio only opens the selected destination. It does not install, configure, or control AlDente, BatFi, or other third-party apps. A known app can use a deep link only after that link is publicly verified; this release configures no deep links for AlDente or BatFi.
