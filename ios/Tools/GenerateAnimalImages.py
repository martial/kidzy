import base64, json, os, sys, time, urllib.request, urllib.error
project = "screen-club"
token = sys.argv[1]
out = sys.argv[2]
animals = {
    "vache": "cow", "chat": "cat", "chien": "dog", "canard": "duck", "mouton": "sheep",
    "coq": "rooster", "lion": "lion", "ane": "donkey", "grenouille": "frog", "cochon": "pig",
}
style = ("Sticker illustration of a friendly {animal} for a toddlers' app. Flat vector style, thick dark navy outline, "
         "bright flat colours, simple rounded shapes, big friendly eyes, a gentle smile, standing, full body, centered, "
         "plain pure white background, no text, no shadow, no border.")
def call(model, location, prompt):
    host = "aiplatform.googleapis.com" if location == "global" else f"{location}-aiplatform.googleapis.com"
    url = f"https://{host}/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent"
    body = {"contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": "1:1"}}}
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read())
chosen = None
for name, animal in animals.items():
    path = os.path.join(out, name + ".png")
    if os.path.exists(path):
        print("have", name); continue
    prompt = style.format(animal=animal)
    data = None; err = None
    for model, location in ([(chosen[0], chosen[1])] if chosen else [("gemini-2.5-flash-image", "global"), ("gemini-2.5-flash-image", "us-central1"), ("gemini-2.5-flash-image-preview", "global")]):
        try:
            resp = call(model, location, prompt)
            parts = resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])
            img = next((p["inlineData"]["data"] for p in parts if "inlineData" in p), None)
            if img:
                data = base64.b64decode(img); chosen = (model, location); break
            err = "no image in response: " + json.dumps(resp)[:300]
        except urllib.error.HTTPError as e:
            err = f"{model}@{location}: HTTP {e.code} {e.read()[:200]!r}"
        except Exception as e:
            err = f"{model}@{location}: {e}"
    if data:
        open(path, "wb").write(data); print("wrote", name, len(data), "bytes via", chosen)
    else:
        print("FAILED", name, err)
    time.sleep(1)
