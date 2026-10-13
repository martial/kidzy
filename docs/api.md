# API

One Go server, JSON over HTTP on port 8800 (LAN). Three access levels:

| Level | How | Who |
|---|---|---|
| public | nothing | discovery and pairing |
| device | `Authorization: Bearer <token>` or `?token=` (for media URLs AVPlayer loads) | the kid app, after pairing with the parent PIN |
| parent | device + `X-Parent-Token` (10 min session from the PIN), or an admin session | the parent area in the app |
| admin | cookie `kidzy_admin` (12 h) + `X-CSRF-Token` on writes + same-origin | the web admin |

Errors are `{"error": "message in French"}` with 400/401/403/404/409/429/500.
Timestamps are Unix milliseconds. Durations are seconds.

## Public

- `GET /healthz` → `ok`
- `GET /api/identity` → `{name, id, version, libraryVersion, serverTime, pinSet}` (Plex: `/identity`)
- `POST /api/pair` `{pin, deviceName}` → `{deviceId, token, name}`; 409 while no PIN exists, 403 wrong PIN, 429 after 6 tries/min.

## Device (the kid app)

- `GET /api/collections` → `{collections: [{id, title, kind, color, itemCount, posterUrl}], libraryVersion}`; only visible collections with at least one playable item, plus a virtual collection `_` titled « Vidéos » when playable items have no collection.
- `GET /api/collections/{id}` → `{collection, items: [{id, collectionId, title, duration, color, thumbUrl, videoUrl}]}` in play order.
- `GET /api/items/{id}` → one item.
- `GET /api/items/{id}/video` → MP4 with HTTP Range (206), `Cache-Control: private`.
- `GET /api/items/{id}/thumb`, `GET /api/collections/{id}/poster` → JPEG.
- `GET /api/finished-image` → the parent's end-of-day JPEG, 404 when none (the app shows its moon).
- `GET /api/hubs` → `{recentlyAdded: [...]}` (Plex: hubs).
- `GET /api/limits` → verdict `{allowed, unlimited, remainingSeconds, watchedSeconds, reason: ""|"daily"|"bedtime", serverTime, rules}`.
- `POST /api/timeline` `{itemId, sessionId, state: playing|paused|stopped|ended, position}` → verdict. Post `playing` every 15 s; the server credits `min(20 s, elapsed since the previous playing event of the session)` (Plex: `/:/timeline`).
- `POST /api/parent/unlock` `{pin}` → `{token, expires}` (parent session, 10 min).

## Parent (app's parent area) and admin

- `GET /api/settings` → `{limits: {dailySeconds, bedtime?: {start, end}}, serverName, finishedImageSet, pinSet, watchedToday, collections: [{id, title, color, visible, itemCount}]}`
- `PUT /api/settings` `{limits?, serverName?, collections?: [{id, visible}]}` → same shape. `serverName` (1–40 characters) is the name shown on the phone and published on Bonjour; `KIDZY_NAME` is only the default.
- `POST /api/settings/pin` `{pin, current}`.
The admin reaches the same three at `/api/admin/settings` and `/api/admin/settings/pin`.

## Admin

Session: `POST /api/admin/setup {pin}` (only while no PIN exists), `POST /api/admin/login {pin}` → `{ok, csrf}` + cookie,
`GET /api/admin/session` → `{ok, csrf?, pinSet, name, version}`, `POST /api/admin/logout`.

Library: `GET /api/admin/library` → `{collections: [collection + {posterUrl, items: [item + {thumbUrl, videoUrl, bytes, width, height}]}], orphans: [...], libraryVersion}`.
Items have `status: importing|ready|failed`, `error`, `source: upload|inbox|youtube`.

Collections: `POST /api/admin/collections {title, kind: show|songs|films}`, `PUT /api/admin/collections/{id} {title?, kind?, color?, visible?}`,
`DELETE /api/admin/collections/{id}` (items stay, without collection), `PUT /api/admin/collections/order {ids}`,
`POST /api/admin/collections/{id}/poster` (multipart `file`), `GET /api/admin/collections/{id}/poster`.

Items: `PUT /api/admin/items/{id} {title?, collectionId?, visible?}`, `DELETE /api/admin/items/{id}` (files removed),
`PUT /api/admin/items/order {ids}`, `POST /api/admin/items/{id}/thumb` (multipart `file`, or JSON `{at}` seconds),
`POST /api/admin/items/{id}/retry` (needs the staged original), `GET /api/admin/items/{id}/thumb|video`.

Upload: `POST /api/admin/upload` multipart with `collectionId` or `collectionTitle` then `file` (one video, up to 8 GB, streamed to staging) → 202 `{itemId, jobId}`.

Jobs: `GET /api/admin/jobs` → `{jobs: [{id, kind, status, stage, progress, log, itemId, created, started, finished}], workerOnline}` (running and queued first, then the 60 most recent),
`POST /api/admin/jobs/{id}/cancel`, `GET /api/admin/events` (SSE: `jobs {jobs}`, `library {version}`, `status {workerOnline}`, `expired`; a comment ping every 15 s).

Other: `GET /api/admin/status`, `GET/POST/DELETE /api/admin/finished-image` (multipart `file`),
`GET /api/admin/devices`, `DELETE /api/admin/devices/{id}` (revoke), `GET /api/admin/sources` → `{sources: [{id, label, status}]}`.

## Ingest

Every source (upload, inbox folder, a source plugin) stages the original in `<data>/staging/<itemId>/original.<ext>` and queues an `ingest` job:
probe → remux (`-c copy`) when the streams are already H.264 4:2:0 ≤1080p + AAC, else transcode with `h264_videotoolbox` (libx264 fallback) → `-movflags +faststart` →
thumbnail (frame at max(5 s, 10 %)) → `~/Kidzy/library/<itemId>/video.mp4` + `thumb.jpg`. Collections' posters live in `~/Kidzy/library/_collections/<id>/poster.jpg`.
