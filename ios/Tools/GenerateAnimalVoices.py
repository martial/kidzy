"""The animals' voices: each animal says its name, then its cry, in the app's language.

Usage: python3 -I ios/Tools/GenerateAnimalVoices.py <token> <out> [fr en es it]
  token = gcloud auth print-access-token (project screen-club); out = ios/Toys/Resources/Sounds.

Files: name-<id>.wav and animal-<id>.wav are French (the default, and Kidzy's language);
name-<id>-<lang>.wav and animal-<id>-<lang>.wav the other languages (AnimalSounds picks them by
the interface language). Gemini TTS (gemini-2.5-flash-tts): names in voice Leda (Kore for the
French duck), cries in voice Puck, each cry the language's own onomatopoeia; trimmed and normalised
with ffmpeg. Existing files are kept: delete one to regenerate it. Listen before shipping.
"""
import base64, json, os, subprocess, sys, time, urllib.request, urllib.error
project = "screen-club"

# id: (name as said to a child, the animal for the prompt, the cry)
ANIMALS = {
    "fr": {
        "vache": ("la vache", "vache", "Meuuuuuh ! Meuh !"), "chat": ("le chat", "chat", "Miaouuu ! Miaou !"),
        "chien": ("le chien", "chien", "Ouaf ! Ouaf ouaf !"), "canard": ("le canard", "canard", "Coin coin ! Coin coin coin !"),
        "mouton": ("le mouton", "mouton", "Bêêêêêh ! Bêêh !"), "coq": ("le coq", "coq", "Cocorico ! Cocoricooo !"),
        "lion": ("le lion", "lion", "Grrrroaaaarrr ! Roaaar !"), "ane": ("l'âne", "âne", "Hi-han ! Hi-han hi-han !"),
        "grenouille": ("la grenouille", "grenouille", "Coâ coâ ! Croâââ !"), "cochon": ("le cochon", "cochon", "Groin groin ! Groin !"),
    },
    "en": {
        "vache": ("Cow!", "cow", "Moooooo! Moo!"), "chat": ("Cat!", "cat", "Meeeooow! Meow!"),
        "chien": ("Dog!", "dog", "Woof! Woof woof!"), "canard": ("Duck!", "duck", "Quack quack! Quack quack quack!"),
        "mouton": ("Sheep!", "sheep", "Baaaaaa! Baa!"), "coq": ("Rooster!", "rooster", "Cock-a-doodle-doo! Cock-a-doodle-doooo!"),
        "lion": ("Lion!", "lion", "Grrrroaaaarrr! Roar!"), "ane": ("Donkey!", "donkey", "Hee-haw! Hee-haw hee-haw!"),
        "grenouille": ("Frog!", "frog", "Ribbit ribbit! Croooak!"), "cochon": ("Pig!", "pig", "Oink oink! Oink!"),
    },
    "es": {
        "vache": ("la vaca", "una vaca", "¡Muuuuuu! ¡Mu!"), "chat": ("el gato", "un gato", "¡Miauuu! ¡Miau!"),
        "chien": ("el perro", "un perro", "¡Guau! ¡Guau guau!"), "canard": ("el pato", "un pato", "¡Cua cua! ¡Cua cua cua!"),
        "mouton": ("la oveja", "una oveja", "¡Beeeeee! ¡Bee!"), "coq": ("el gallo", "un gallo", "¡Quiquiriquí! ¡Quiquiriquííí!"),
        "lion": ("el león", "un león", "¡Grrrroaaaarrr! ¡Roar!"), "ane": ("el burro", "un burro", "¡Iii-aaa! ¡Iii-aaa iii-aaa!"),
        "grenouille": ("la rana", "una rana", "¡Croac croac! ¡Croooac!"), "cochon": ("el cerdo", "un cerdo", "¡Oinc oinc! ¡Oinc!"),
    },
    "it": {
        "vache": ("la mucca", "una mucca", "Muuuuuu! Muu!"), "chat": ("il gatto", "un gatto", "Miaooo! Miao!"),
        "chien": ("il cane", "un cane", "Bau! Bau bau!"), "canard": ("l'anatra", "un'anatra", "Qua qua! Qua qua qua!"),
        "mouton": ("la pecora", "una pecora", "Beeeeee! Bee!"), "coq": ("il gallo", "un gallo", "Chicchirichì! Chicchirichììì!"),
        "lion": ("il leone", "un leone", "Grrrroaaaarrr! Roar!"), "ane": ("l'asino", "un asino", "I-oo! I-oo i-oo!"),
        "grenouille": ("la rana", "una rana", "Cra cra! Craaa!"), "cochon": ("il maiale", "un maiale", "Oink oink! Oink!"),
    },
}
LOCALE = {"fr": "fr-FR", "en": "en-US", "es": "es-ES", "it": "it-IT"}
NAME_PROMPT = {
    "fr": "Lis une seule fois, doucement et joyeusement, exactement ces mots et rien d'autre, sans imiter l'animal : {name}",
    "en": "Read once, softly and cheerfully, exactly these words and nothing else, without imitating the animal: {name}",
    "es": "Lee una sola vez, con dulzura y alegría, exactamente estas palabras y nada más, sin imitar al animal: {name}",
    "it": "Leggi una sola volta, con dolcezza e allegria, esattamente queste parole e nient'altro, senza imitare l'animale: {name}",
}
CRY_PROMPT = {
    "fr": "Tu es un {animal} de dessin animé. Fais seulement son cri, de façon exagérée et rigolote, sans aucun autre mot : {cry}",
    "en": "You are a cartoon {animal}. Make only its sound, exaggerated and funny, with no other words: {cry}",
    "es": "Eres {animal} de dibujos animados. Haz solo su sonido, de forma exagerada y divertida, sin ninguna otra palabra: {cry}",
    "it": "Sei {animal} dei cartoni animati. Fai solo il suo verso, in modo esagerato e buffo, senza nessun'altra parola: {cry}",
}


def call(token, model, location, text, voice, language):
    host = "aiplatform.googleapis.com" if location == "global" else f"{location}-aiplatform.googleapis.com"
    url = f"https://{host}/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent"
    body = {"contents": [{"role": "user", "parts": [{"text": text}]}],
            "generationConfig": {"responseModalities": ["AUDIO"], "speechConfig": {"languageCode": LOCALE[language], "voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}}}}
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read())


def synth(token, path, text, voice, language):
    err = None
    for model, location in [("gemini-2.5-flash-tts", "global"), ("gemini-2.5-flash-tts", "us-central1"), ("gemini-2.5-flash-preview-tts", "global"), ("gemini-2.5-flash-preview-tts", "us-central1")]:
        try:
            resp = call(token, model, location, text, voice, language)
            parts = resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])
            part = next((p for p in parts if "inlineData" in p), None)
            if not part:
                err = "no audio: " + json.dumps(resp)[:200]
                continue
            mime = part["inlineData"].get("mimeType", "")
            raw = base64.b64decode(part["inlineData"]["data"])
            rate = 24000
            for kv in mime.split(";"):
                if kv.strip().startswith("rate="):
                    rate = int(kv.split("=")[1])
            pcm = path + ".pcm"
            open(pcm, "wb").write(raw)
            # trim silence, normalise, fade out, 44.1 kHz mono
            subprocess.run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(rate), "-ac", "1", "-i", pcm,
                            "-af", "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.08,areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.15,areverse,loudnorm=I=-16:TP=-1.5,afade=t=out:st=9:d=0.5",
                            "-t", "6", "-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", path], check=True)
            os.remove(pcm)
            return model + "@" + location
        except urllib.error.HTTPError as e:
            err = f"{model}@{location}: HTTP {e.code} {e.read()[:160]!r}"
        except Exception as e:
            err = f"{model}@{location}: {e}"
    return "FAILED " + str(err)


def main():
    token, out = sys.argv[1], sys.argv[2]
    for language in sys.argv[3:] or list(ANIMALS):
        suffix = "" if language == "fr" else "-" + language
        for id, (name, animal, cry) in ANIMALS[language].items():
            n = os.path.join(out, f"name-{id}{suffix}.wav")
            if not os.path.exists(n):
                voice = "Kore" if (id, language) == ("canard", "fr") else "Leda"
                print(language, id, "name:", synth(token, n, NAME_PROMPT[language].format(name=name), voice, language))
            c = os.path.join(out, f"animal-{id}{suffix}.wav")
            if not os.path.exists(c):
                print(language, id, "cry: ", synth(token, c, CRY_PROMPT[language].format(animal=animal, cry=cry), "Puck", language))
            time.sleep(0.5)


if __name__ == "__main__":
    main()
