---
name: run-server
description: Start, stop, restart, watch the log of, or reset the Kidzy server on this Mac. Use whenever Martial says "lance le serveur", "redémarre", "le serveur tourne ?", "les logs", "remets à zéro la bibliothèque", or when a change in server/ needs to be seen live on the phone.
---
# Run the Kidzy server

- Foreground, for development: `make run` (reads `~/.config/kidzy/kidzy.env`, listens on :8800).
- Background service (what the family uses): `ops/install-launchd.sh` builds, installs the
  LaunchAgent `com.screenclub.kidzy` and starts it. Rerun it after any server change.
- Log: `tail -f ~/Library/Logs/Kidzy/kidzy.log`. Health: `curl -s localhost:8800/healthz`.
- Stop: `launchctl bootout gui/$(id -u)/com.screenclub.kidzy`.
- Bonjour check: `dns-sd -B _kidzy._tcp` must list the server name within a second.
- Reset everything (asks Martial first): stop, delete `~/Library/Application Support/Kidzy/`
  and `~/Kidzy/library/`, start again. The inbox is never deleted.
