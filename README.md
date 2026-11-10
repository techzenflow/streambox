# Streambox

A Flutter media player starter with WebDAV browsing and video playback.

## Run

```sh
flutter pub get
flutter run -d chrome
```

Flutter runner projects are included for Android, iOS, Web, Windows, macOS, and Linux. Run with the target device available in `flutter devices`.

## Connect a WebDAV server

Enter the server's WebDAV root URL, then its username and password. The app uses `PROPFIND` with `Depth: 1` to browse folders and sends Basic authentication for requests. Video and audio playback is provided by `video_player` and depends on the codecs supported by the target platform.

For Web builds, the WebDAV server must allow cross-origin requests from the app origin, including the `PROPFIND` method and the `Authorization` request header. Browser media playback also requires the server to permit cross-origin media requests and support byte-range requests for seeking.

## Current scope

- Browse folders and list common video and audio formats.
- Filter media by type and play supported files.
- Credentials are kept in memory for the current app session; they are not saved.
- The first version does not include playlists, subtitle tracks, background playback, or persistent connection profiles.
