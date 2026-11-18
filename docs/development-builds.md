# Local development builds

Run `bash scripts/build-dev-app.sh release open` to build the isolated developer app at `dist-dev/Status Trio Dev.app`. The developer bundle identifier and output location remain separate from production, and the build disables production Sparkle updates.

By default, the script runs `security find-identity -v -p codesigning` and selects the SHA-1 only when exactly one valid `Developer ID Application` identity is available. No match or multiple matches stop the build with an instruction to choose explicitly; the script never falls back silently to Apple Development or ad-hoc signing.

Set `CODE_SIGN_IDENTITY` to choose an identity by SHA-1 or signing name. Set it to `-` only when an ad-hoc developer build is intentional. `codesign` may still show a keychain authorization prompt; the build does not suppress or bypass that prompt.
