# Streambox

A Flutter media player starter with WebDAV browsing and video playback.

## Run

```sh
flutter pub get
flutter run -d chrome
```

Flutter runner projects are included for Android, iOS, Web, Windows, macOS, and Linux. Run with the target device available in `flutter devices`.

## Releases

- Every push to `main` builds an Android APK and publishes a versioned GitHub **pre-release**, such as `v1.0.0-beta.12`. GitHub generates notes from the changes since the previous release.
- A stable Android release is published by pushing a version tag such as `v1.0.0`. Stable releases are separate from beta releases and are not replaced by beta builds.
- Download APKs from [GitHub Releases](https://github.com/techzenflow/streambox/releases).

The APK's version name matches its release tag (without the leading `v`). Its Android build number is the GitHub Actions run number.

## Connect a WebDAV server

Enter the server's WebDAV root URL, then its username and password. The app uses `PROPFIND` with `Depth: 1` to browse folders and sends Basic authentication for requests. Video and audio playback is provided by `video_player` and depends on the codecs supported by the target platform.

For Web builds, the WebDAV server must allow cross-origin requests from the app origin, including the `PROPFIND` method and the `Authorization` request header. Browser media playback also requires the server to permit cross-origin media requests and support byte-range requests for seeking.

## Current scope

- Browse folders and list common video and audio formats.
- Filter media by type and play supported files.
- Credentials are kept in memory for the current app session; they are not saved.
- The first version does not include playlists, subtitle tracks, background playback, or persistent connection profiles.
