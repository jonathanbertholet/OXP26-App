# Google Play publishing

App: **OXP26** · package: **be.oxp.app** · default language: **en-US**.

Fastlane is installed locally in `vendor/bundle`, with versions recorded in `Gemfile.lock`. The `scripts/play` wrapper uses this installation and disables Fastlane usage reporting. Reinstall on another machine with:

```sh
cd android
BUNDLE_PATH=vendor/bundle BUNDLE_APP_CONFIG=.bundle bundle install
scripts/play doctor
```

## Current setup

- Local upload key and release signing are configured. Private files live in the ignored `.secrets/` directory, with access restricted to the local user.
- `.secrets/oxp-upload-certificate.pem` is the public upload certificate.
- `app/build/outputs/bundle/release/app-release.aab` is the release artifact.
- OXP26 is created in Play Console as a free app, package `be.oxp.app`, app ID `4974406182491762503`. An internal release draft has its name and release notes saved.
- The Google Play publishing API is connected through project `airy-signer-445520-s5` and service account `oxp26-publisher@airy-signer-445520-s5.iam.gserviceaccount.com`. Its Play access is restricted to OXP26 app information (including dependent app-quality read access) and releases to testing tracks.
- The credential is stored in `.secrets/google-play.json` with permissions `600`. The wrapper automatically uses it when neither credential environment variable is set. It is excluded from version control.
- `scripts/play check_connection` successfully authenticated and read OXP26's internal track on 5 September 2026. At that check, the track had no version codes.
- The first signed bundle, version code **1** / version name **1.0**, was successfully uploaded and saved through the CLI as an internal draft on 5 September 2026. The API accepted the first upload without a manual browser upload.
- This account's Play Console currently requires a closed test with at least 12 opted-in testers for 14 days before applying for production access. Internal testing can be prepared first.

Back up the upload keystore **and** its password from `.secrets/upload.properties` in your password manager or another secure backup before relying on this machine for updates. Do not commit the `.secrets/` directory or send its contents in chat.

## First-time Google setup

1. Open the existing [OXP26 app](https://play.google.com/console/u/0/developers/8189227781932730799/app/4974406182491762503/app-dashboard). The package must remain `be.oxp.app` to match the app and CLI configuration.
2. Enable the Google Play Android Developer API in a Google Cloud project.
3. Create a publishing service account and grant it app-level access to OXP26 through Play Console **Users and permissions**. Use the app-information and testing-release permissions needed for internal drafts; store-listing and production-release permissions can be added when those workflows are authorized. Account-wide admin and financial access are unnecessary for this workflow.
4. Store its credentials JSON locally as `.secrets/google-play.json` with file permissions `600`. Set the credential path before using the CLI:

   ```sh
   export SUPPLY_JSON_KEY="$PWD/.secrets/google-play.json"
   ```

5. If Google rejects a first API upload for an uninitialized app, upload the first signed bundle in Play Console and configure Play App Signing. Browser uploads require the ChatGPT Chrome extension's **Allow access to file URLs** setting.
6. Run `scripts/play check_connection` to authenticate and read OXP26's internal track. This does not upload or commit a release.

The account owner's policy declarations, app-content forms, store listing, and any Play testing/production-access requirements must also be completed before a public release.

## Build and prepare subsequent releases

Use JDK 17 or newer with the Android SDK configured. `JAVA_HOME` can point to your local JDK.

```sh
scripts/play build_release version_code:2 version_name:1.0.1
scripts/play upload_internal_draft
```

Choose a version code higher than every previously uploaded build; version code 1 is used for the first release. Both build and upload verify the bundle signature. Uploads go to **internal testing as a draft**. The uploader requests that changes be held from review; if Google requires the review parameter to be omitted, Fastlane retries the same save with Google's required setting. The release status remains `draft`, which does not serve the build to users. This command does not publish to production or replace store text/screenshots. Review and release the draft in Play Console when ready.

Signing can also be supplied through `OXP_UPLOAD_STORE_FILE`, `OXP_UPLOAD_STORE_PASSWORD`, `OXP_UPLOAD_KEY_ALIAS`, and `OXP_UPLOAD_KEY_PASSWORD`, which take precedence over local properties. Keep credentials in your secret manager when using CI.

References: [Google API setup](https://developers.google.com/android-publisher/getting_started), [Fastlane Supply](https://docs.fastlane.tools/actions/supply/), [Android signing](https://developer.android.com/studio/publish/app-signing).
