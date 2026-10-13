import base64, json, os, subprocess, sys, time, urllib.request, urllib.error
project = "screen-club"; token = sys.argv[1]; out = sys.argv[2]
animals = {
    "vache": ("la vache", "Meuuuuuh ! Meuh !"), "chat": ("le chat", "Miaouuu ! Miaou !"), "chien": ("le chien", "Ouaf ! Ouaf ouaf !"),
    "canard": ("le canard", "Coin coin ! Coin coin coin !"), "mouton": ("le mouton", "Bêêêêêh ! Bêêh !"), "coq": ("le coq", "Cocorico ! Cocoricooo !"),
    "lion": ("le lion", "Grrrroaaaarrr ! Roaaar !"), "ane": ("l'âne", "Hi-han ! Hi-han hi-han !"), "grenouille": ("la grenouille", "Coâ coâ ! Croâââ !"), "cochon": ("le cochon", "Groin groin ! Groin !"),
}
def call(model, location, text, voice):
    host = "aiplatform.googleapis.com" if location == "global" else f"{location}-aiplatform.googleapis.com"
    url = f"https://{host}/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent"
    body = {"contents": [{"role": "user", "parts": [{"text": text}]}],
            "generationConfig": {"responseModalities": ["AUDIO"], "speechConfig": {"languageCode": "fr-FR", "voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}}}}
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r: return json.loads(r.read())
def synth(path, text, voice):
    err = None
    for model, location in [("gemini-2.5-flash-tts", "global"), ("gemini-2.5-flash-tts", "us-central1"), ("gemini-2.5-flash-preview-tts", "global"), ("gemini-2.5-flash-preview-tts", "us-central1")]:
        try:
            resp = call(model, location, text, voice)
            parts = resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])
            part = next((p for p in parts if "inlineData" in p), None)
            if not part: err = "no audio: " + json.dumps(resp)[:200]; continue
            mime = part["inlineData"].get("mimeType", ""); raw = base64.b64decode(part["inlineData"]["data"])
            rate = 24000
            for kv in mime.split(";"):
                if kv.strip().startswith("rate="): rate = int(kv.split("=")[1])
            pcm = path + ".pcm"; open(pcm, "wb").write(raw)
            # trim silence, normalise, fade out, 44.1 kHz mono
            subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(rate), "-ac", "1", "-i", pcm,
                            "-af", "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.08,areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.15,areverse,loudnorm=I=-16:TP=-1.5,afade=t=out:st=9:d=0.5",
                            "-t", "6", "-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", path], check=True)
            os.remove(pcm)
            return model + "@" + location
        except urllib.error.HTTPError as e: err = f"{model}@{location}: HTTP {e.code} {e.read()[:160]!r}"
        except Exception as e: err = f"{model}@{location}: {e}"
    return "FAILED " + str(err)
for name, (label, cry) in animals.items():
    n = os.path.join(out, f"name-{name}.wav")
    if not os.path.exists(n):
        print(name, "name:", synth(n, f"Lis une seule fois, doucement et joyeusement, exactement ces mots et rien d'autre, sans imiter l'animal : {label}.", "Kore" if name == "canard" else "Leda"))
    c = os.path.join(out, f"animal-{name}.wav")
    if not os.path.exists(c):
        print(name, "cry: ", synth(c, f"Tu es un {label.split(' ',1)[1] if ' ' in label else label} de dessin animé. Fais seulement son cri, de façon exagérée et rigolote, sans aucun autre mot : {cry}", "Puck"))
    time.sleep(0.5)
