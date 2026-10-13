# Tools

- `GenerateIcon.swift`: the app icon (sun mascot), 1024 px PNG without alpha.
- `GenerateSounds.py <out> [animals]`: synthesized toy sounds (splash, plop, bump, giggle, chime) and, with `animals`, cartoon cries kept as a fallback.
- `GenerateAnimalImages.py <token> <out>`: the ten animal stickers with Gemini (`gemini-2.5-flash-image`, project screen-club); token = `gcloud auth print-access-token`.
- `GenerateAnimalVoices.py <token> <out>`: the names (voice Leda, Kore for the duck) and the cries (voice Puck) with Gemini TTS (`gemini-2.5-flash-tts`), trimmed and normalised with ffmpeg.
- `TranscribeClips.py <token> <dir>`: asks Gemini what each clip says, to check the voice spoke only the words wanted.

The generated files live in `Kidzy/Resources/Animals/` and `Kidzy/Resources/Sounds/`; regenerate only on purpose, listen before shipping.
