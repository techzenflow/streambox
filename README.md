# Streambox

A Flutter video player for watching videos stored on your device, with WebDAV as an optional remote library.

## Features

- Mobile-first home screen for opening and playing local video files.
- Select multiple videos to create a playback queue, scan a local folder, and reopen recent files.
- Player controls for seeking, 10-second jumps, speed (0.25x–4x), aspect ratio, queue navigation, and immersive landscape playback.
- Settings for fullscreen rotation, hiding system bars, auto-hiding controls, default speed, and local playback history.
- Browse a WebDAV server and play supported video or audio files when you choose the optional WebDAV source.
- Android, iOS, Windows, macOS, Linux, and Web targets. Playback support depends on the target platform and media format.

The app uses `file_picker` to select local media and `video_player_media_kit` with the media_kit platform libraries to extend playback across desktop and mobile targets. Web playback uses a browser object URL for the selected file.

## Run

```sh
flutter pub get
flutter run
```

Flutter runner projects are included for Android, iOS, Web, Windows, macOS, and Linux. Run with the target device available in `flutter devices`.

## Releases

- Every push to `main` builds Android APKs and publishes a versioned GitHub **pre-release**, such as `v1.0.0-beta.12`, with generated notes and a changelog.
- Android beta and stable releases provide one universal APK plus APKs for individual CPU architectures. Use the universal APK if you are unsure which architecture to choose.
- A stable Android release is published by pushing a version tag such as `v1.0.0`. Stable releases remain separate from beta releases.
- Download builds from [GitHub Releases](https://github.com/techzenflow/streambox/releases).

GitHub Actions signs each release with a persistent Android release key stored in repository Actions Secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`) so future versions can update an existing installation.

The first release that uses this persistent key cannot update older beta installations, which were signed with temporary build keys. Uninstall an older beta once before installing the first persistently signed release; updates after that will install normally.

The APK version matches its release tag (without the leading `v`), and its Android build number is the GitHub Actions run number.

## Optional WebDAV library

Switch the media source to WebDAV, then enter the server's WebDAV root URL, username, and password. Credentials are kept in memory for the current session and are not saved. The app browses with `PROPFIND` and Basic authentication.

For Web builds, the WebDAV server must allow cross-origin requests from the app origin, including the `PROPFIND` method and `Authorization` request header. Browser media playback also requires cross-origin media requests and byte-range support for seeking.

## Current scope

The local library uses the system file picker and can scan a selected folder on Windows, macOS, and Linux. Android and iOS use the system file picker to select videos. Folder scanning is not available on mobile or in the Web build. WebDAV credentials remain in memory and are not saved. Subtitle and audio track selection, picture-in-picture, and background playback are not included yet.

