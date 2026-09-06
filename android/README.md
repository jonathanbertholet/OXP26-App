# OXP for Android

Native Kotlin / Jetpack Compose companion for Odoo Experience 2026. Requires Android 8.0 (API 26) or newer. Open this directory in Android Studio, sync Gradle, and run `app`.

## Build

Use JDK 17 or newer, Android SDK Platform 36.1, and the included Gradle wrapper. Configure the Android SDK using Android Studio, `ANDROID_HOME`, or an untracked `local.properties` file containing `sdk.dir=/absolute/path/to/sdk`.

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug
```

Install `app/build/outputs/apk/debug/app-debug.apk` on an Android device or emulator. `scripts/play build_release` produces a signed release bundle using local upload credentials. See [Google Play publishing](PUBLISHING.md) for the Fastlane CLI connection and release workflow. Release credentials are excluded from Git.

## Features

- Today: edition-local time, happening now, upcoming and featured talks, conference-day preview.
- Schedule: day, topic/audience, kind and saved filters; text search; list and room/time agenda with overlap lanes.
- Map: Belgium-only hall plans, zoom/pan, room and amenity search, individual booths and rows, room agendas, and links from talk details. An accessible place list accompanies the visual map.
- Expo: edition-specific company listings, sponsor levels, country/search filters and official website links.
- Saved: local persistence, grouping across editions, conflict indicators, configurable reminders, and notification actions to open or remove a talk.
- Settings: manual agenda refresh, offline/update status, notification controls, privacy and support links.
- System dark mode, Android back handling, text scaling, and share sheets.

The map retains the existing iOS app’s simplified hall geometry. Individual exhibitor-to-booth assignments are not present in the source catalog. Speaker and exhibitor text is available offline. Photos and logos load when connected and use local image caching; external pages require a connection.

## Shared data

`sharedAssets` copies the existing `../OXP/Resources/catalog.json` into generated Android build assets. Hall plans render as native vectors using the current iOS room, booth, and outer-wall geometry; the legacy map PNGs are no longer bundled. There is no second copy of the catalog to maintain. Map hit regions are generated in `VenueData.kt` from the iOS `VenueLayout.swift` and `FloorMapCanvas.swift`. Run `python3 android/scripts/sync_venue.py` from the repository root after changing that geometry; it also preserves all 229 numbered booth positions.

The live feed is the same HTTPS endpoint as iOS. Updates validate the schema, timestamps, edition membership, track IDs, minimum track counts, time zones and interval order before replacing the atomic offline cache. ETags support conditional requests. The original bundled catalog intentionally predates the versioned feed format. It remains the startup fallback when cache restoration or a refresh fails.

Automatic checks use the same September 2026 conference windows and two-hour throttle as iOS; manual checks work any time. All comparisons and reminders use real instants, independent of the preview clock. Empty editions and sessions with unpublished times are supported.

## Reminders

Saving a talk requests notification permission on Android 13+. If access is denied, the talk is still saved. Settings links to notification permissions and optional precise-alarm access. Without precise-alarm access, Android may delay reminders. Alarms are rebuilt after a feed update, app resume, device restart, or app update, and cancelled for removed/unavailable talks. Preview mode never changes notification timing.

Favorites are local to the Android installation and are not synced with iOS. There is no login or analytics SDK. Backup is disabled for this first Android version.

## Verification

Unit tests cover the real five-edition catalog, feed rejection cases, overlap detection and agenda placement, conference refresh windows, URL normalization, and Brussels room aliases. See the repository’s Android CI workflow for repeatable build, unit-test and lint checks. Before a store release, also test notifications on physical devices, where battery and notification policies vary by manufacturer.
