# Automatic agenda updates

The iOS app downloads `https://oxp-site.jonathanbertholet.workers.dev/agenda/catalog.json` at launch, when returning to the foreground (with a five-minute throttle), and every five minutes while open. Pull to refresh or choose **Refresh agenda** from the edition menu to check immediately. Odoo source freshness for the selected edition appears in that menu.

GitHub Actions checks Odoo approximately hourly, or every 15 minutes from the day before an edition through its last day. GitHub schedules can be delayed; this is polling, not a real-time push service. Talk details refresh daily; new talks and changed presenters refresh immediately. Exhibitor information currently remains the bundled snapshot. No database or Cloudflare credential is stored in GitHub.

The `Update agenda` workflow runs on the default branch, uses `scripts/update_agenda.py`, and commits only validated output to `codex/agenda-feed`. The Cloudflare Worker streams that public file and caches it for up to 60 seconds. Favorites remain on the device, keyed by Odoo's talk IDs. The app keeps its last valid feed atomically and always has the bundled agenda as a fallback. A removed talk remains accessible in Saved with an explanation, and its reminder is removed. Changed talk times update authorized local reminders when the app next refreshes; a closed app cannot learn changes until reopened.

## Failure handling

Each edition updates independently. Empty/duplicate listings, a loss of more than 10% of existing talks, or lost schedule times retain that edition's previous agenda and source timestamp. A warning identifies the edition in the workflow log. If every edition fails, the workflow fails and publishes nothing. Individual detail-page failures preserve previous descriptions. Missing editions, duplicate talk IDs, invalid durations, oversized feeds, and unsupported schema versions are rejected. The app also rejects stale feed revisions and invalid snapshots.

US, Mexico, and Kenya source listings were unavailable or substantially reduced during the first refresh on 5 September 2026, so their included agendas were retained. India and Belgium refreshed successfully. Review a flagged source before changing the disappearance guard.

## Operations

- Run **Actions → Update agenda → Run workflow** for an immediate refresh. A failed run leaves the last published feed intact; inspect warnings even on successful runs for retained editions.
- GitHub may disable scheduled workflows after 60 days without repository activity in public repositories. Check that this workflow is enabled before the next event.
- For a rollback, take the last good `catalog.json` from feed-branch history, give it a new `generated_at`, and preserve or advance per-edition `source_checked_at` timestamps after reviewing the source. The app intentionally rejects older snapshots.
- Deploy Worker or site changes with `npx --yes wrangler@4.129.0 deploy` after `deploy --dry-run`. This requires the maintainer's local Cloudflare login.
- Validate the updater with `python3 -m unittest discover -s scripts/tests`; validate the app with the OXP Xcode test scheme.

The endpoint is public and contains public event information only. App users' saved talks and location are never sent to the feed service.
