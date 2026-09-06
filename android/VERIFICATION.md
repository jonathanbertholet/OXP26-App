# Android port verification

Verified on 5 September 2026 with the Android 36.1 ARM64 emulator, JDK 17, and the bundled Gradle wrapper.

## Automated checks

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug :app:bundleRelease
```

Eight JVM tests exercise the actual bundled catalog and cover separate editions, empty programs, versioned feed validation, rollback/missing-event/duplicate-track rejection, invalid time zones and intervals, conflict detection, agenda overlap lanes, refresh throttling, URL normalization, and venue coverage. Venue regeneration preserves 50 mapped features and 229 numbered booths. The APK contains the shared catalog. All four hall plans use native vectors generated from the current iOS geometry.

Lint has no errors. Nonblocking dependency-update, style, launcher-shape, and custom-view accessibility advisories remain; the map has a parallel accessible place list.

## Emulator checks

- Launch and render the bundled Belgium agenda.
- Save a talk, deny notification permission, and confirm it remains saved after a full app restart.
- Switch to India: Map disappears, while Belgium’s saved talk remains available under its own edition.
- Switch back to Belgium; select 24 September and the time/room agenda.
- Switch tabs and retain the chosen schedule day and layout.
- Render Hall 7 with portrait rotation, upright labels, working surrounding controls, and an accessible place list.
- Disable emulator Wi-Fi and mobile data, cold-launch the app, and confirm the live catalog and saved talk remain available offline.
- Browse the offline exhibitor list.
- Download and validate the live feed; confirm the atomic cache contains schema version 1 and all five editions.

Screenshots: [Agenda](screenshots/agenda.png), [Shared agenda events](screenshots/agenda-shared.png), [Today](screenshots/today.png), [Map](screenshots/map.png), [Room sessions](screenshots/map-room.png), [Place description](screenshots/map-place.png).

The focused visual pass uses the current iOS vector footprints, neutral surfaces, plum accents, room-color time gutters, heart saves, and softer navigation and filters. The updated APK and release bundle build successfully; all seven existing tests pass and lint reports no errors.

The subsequent navigation and map interaction pass refines the bottom bar with a single selection background around each icon and label. Tapping a map zone now opens a dismissible sheet with room sessions, booth information, or the shared iOS amenity description. Rooms default to all available days outside their scheduled dates. Emulator checks confirmed a direct Hall 7.A map tap, opening its talk, returning to the map, and opening and dismissing the Hall 7 catering description. The updated debug APK is installed in the running emulator; all seven tests pass and lint has no errors. The release bundle predates this interaction pass.

The agenda refinement removes the separate shared-event column and repeats those events in every venue column, including when filters hide the room’s other sessions. A regression test covers replication, duplicate prevention, filtered views, and unassigned talks. Cards now include tag chips, topic-based accent colors, wider column gaps and more internal spacing. Emulator checks confirmed repeated opening/keynote events and readable tags on half-hour talks. The final debug build passes all eight tests and lint has no errors.

Navigation now uses directional fade/slide transitions (140–280 ms), reversing on Back, with a fading title, animated tab emphasis, and an expanding/collapsing bottom bar. Emulator checks confirmed Schedule → Map → Schedule preserves the September 24 Agenda view, and opening/closing both a talk and Settings restores the agenda without runtime errors. The animated debug build is installed; all eight tests pass and lint has no errors.

## Release work

The debug APK is installable. The current release AAB is signed with the local OXP26 upload key, and its signature was verified with the JDK tooling. Fastlane 2.239.0 is installed with a locked dependency set and working local build/doctor lanes. Google Play app creation and API authorization are still pending; see PUBLISHING.md. Physical-device notification timing, manufacturer battery restrictions, TalkBack operation, and minimum-version device testing still need a release QA pass. No Play Store upload was performed.
