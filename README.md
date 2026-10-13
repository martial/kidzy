# Kidzy

A video player for small kids that their parent fully controls.

- **iPhone app** (`ios/`): a bright library of big tiles, a full-screen player that can only be
  left with 4 taps in the top-left corner, a parent area behind a PIN, time limits that leave the
  app on a picture when the day's quota is reached.
- **Server** (`server/`): one Go binary that runs on the family Mac. It watches `~/Kidzy/inbox/`,
  normalises every video to an iPhone-native MP4 (H.264 + AAC), keeps a small SQLite catalogue,
  serves the files over HTTP Range and advertises itself on the LAN with Bonjour (`_kidzy._tcp`).
  A minimal take on what Plex does, without the parts a family doesn't need.
- **Admin** (`admin/`): a small React page embedded in the binary at `/admin/` to drop videos,
  organise collections, set the limits and watch the jobs.

See `CLAUDE.md` for the map of the repo and `docs/` for the design, API and procedures.
