"""Three frames of the parrot sticker for « Perroquet »: idle, talk (beak open), listen (head tilted).
Usage: python3 GenerateParrotImages.py "$(gcloud auth print-access-token)" ../Kidzy/Resources/Parrot
The talk and listen frames are edits of the idle frame so the bird stays the same."""
import base64, json, os, sys, time, urllib.request, urllib.error
project = "screen-club"
token = sys.argv[1]
out = sys.argv[2]
style = ("Sticker illustration of a friendly parrot for a toddlers' app. Flat vector style, thick dark navy outline, "
         "bright flat colours (red body, blue and yellow wing feathers, white eye patch), simple rounded shapes, big friendly eyes, "
         "beak closed with a gentle smile, standing on nothing, full body, facing the viewer slightly to the left, centered, "
         "plain pure white background, no text, no shadow, no border.")
edits = {
    "talk": "Edit this sticker: the very same parrot, same style, same colours, same pose and size, but with its beak wide open as if it were talking loudly, eyes wide and happy. Plain pure white background, no text.",
    "listen": "Edit this sticker: the very same parrot, same style, same colours, same size, but with its head tilted to one side and one wing raised cupped next to the side of its head as if listening carefully, eyes looking up curiously. Plain pure white background, no text.",
}
def call(model, location, parts):
    host = "aiplatform.googleapis.com" if location == "global" else f"{location}-aiplatform.googleapis.com"
    url = f"https://{host}/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent"
    body = {"contents": [{"role": "user", "parts": parts}],
            "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": "1:1"}}}
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read())
def generate(name, parts):
    path = os.path.join(out, f"parrot-{name}.png")
    if os.path.exists(path):
        print("have", name); return open(path, "rb").read()
    err = None
    for model, location in [("gemini-2.5-flash-image", "global"), ("gemini-2.5-flash-image", "us-central1")]:
        try:
            resp = call(model, location, parts)
            rparts = resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])
            img = next((p["inlineData"]["data"] for p in rparts if "inlineData" in p), None)
            if img:
                data = base64.b64decode(img)
                open(path, "wb").write(data); print("wrote", name, len(data), "bytes via", model, location); return data
            err = "no image in response: " + json.dumps(resp)[:300]
        except urllib.error.HTTPError as e:
            err = f"{model}@{location}: HTTP {e.code} {e.read()[:200]!r}"
        except Exception as e:
            err = f"{model}@{location}: {e}"
        time.sleep(1)
    print("FAILED", name, err); return None
base = generate("idle", [{"text": style}])
if base:
    ref = {"inlineData": {"mimeType": "image/png", "data": base64.b64encode(base).decode()}}
    for name, prompt in edits.items():
        generate(name, [ref, {"text": prompt}])
