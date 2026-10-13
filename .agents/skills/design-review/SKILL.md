---
name: design-review
description: Show Kidzy screen mock-ups to Martial on his phone and record his approval before building them. Use whenever a new screen or a visual change is planned, or Martial says "montre-moi", "les maquettes", "le design", "à quoi ça ressemble".
---
# Design review

- Mock-ups live in `docs/design/` as self-contained HTML pages at iPhone size (kid screens: no
  text to read, big tiles, bright colours). `docs/design/README.md` lists each page and its status.
- Share them: publish `docs/design/index.html` as a private Artifact (one page with all screens)
  and give Martial the link; on the LAN, `python3 -m http.server 8787 -d docs/design` also works.
- Iterate on his remarks in the HTML, republish to the same URL.
- When he approves, write the date and the artifact URL in `docs/design/README.md`. Only then
  change the app. If the app later drifts from the mock-ups, update the mock-ups first.
