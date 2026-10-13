import base64, json, os, sys, urllib.request, urllib.error
project = "screen-club"; token = sys.argv[1]; d = sys.argv[2]
def call(path):
    url = f"https://aiplatform.googleapis.com/v1/projects/{project}/locations/global/publishers/google/models/gemini-2.5-flash:generateContent"
    audio = base64.b64encode(open(path, "rb").read()).decode()
    body = {"contents": [{"role": "user", "parts": [{"inlineData": {"mimeType": "audio/wav", "data": audio}},
            {"text": "Transcris exactement et uniquement ce qui est dit ou crié dans cet extrait, en français, sans commentaire. Si c'est un cri d'animal imité, écris l'onomatopée."}]}],
            "generationConfig": {"temperature": 0}}
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        resp = json.loads(r.read())
    return "".join(p.get("text", "") for p in resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])).strip()
for f in sorted(os.listdir(d)):
    if not f.endswith(".wav"): continue
    try: print(f"{f:24s} → {call(os.path.join(d, f))[:90]}")
    except urllib.error.HTTPError as e: print(f, "HTTP", e.code, e.read()[:120])
