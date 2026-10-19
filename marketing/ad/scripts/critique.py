"""Ask Gemini (Vertex) to critique a storyboard sheet. python3 -I critique.py TOKEN SHEET.png [model]"""
import base64, json, sys, urllib.request
token, sheet = sys.argv[1], sys.argv[2]
model = sys.argv[3] if len(sys.argv) > 3 else "gemini-3.1-pro-preview"
prompt = """You are the creative director of a top toy-commercial studio. These are 8 styleframes (left to right, top row then bottom row)
for a 20-second vertical Instagram ad for a kids' iPhone app called "Sketches for kids!" (six toys: sea with a boat, paint that mixes
like real paint, shapes that play marimba, animals, a guitar, a talking parrot). Concept "The toys break out": 1 the parrot bursts out of
the phone, 2 water floods out and the boat surfs it, 3 blue and yellow paint spiral out and turn green where they meet, 4 the guitar
strums itself while the shapes rain down, 5 the cow jumps out, 6 the real app on the phone (a child's finger painting), 7 everything gets
sucked back into the phone, 8 end card. They are rendered in Blender (3D set + cut-out toy art on cards). Be blunt and specific: for each
frame, the single biggest problem and the concrete fix (composition, lighting, scale, readability, what looks fake or amateur). Then the
3 changes that would most raise the whole set toward a premium, high-energy commercial. Keep it under 350 words."""
body = {"contents": [{"role": "user", "parts": [{"inlineData": {"mimeType": "image/png", "data": base64.b64encode(open(sheet, "rb").read()).decode()}}, {"text": prompt}]}],
        "generationConfig": {"temperature": 0.4}}
url = f"https://aiplatform.googleapis.com/v1/projects/screen-club/locations/global/publishers/google/models/{model}:generateContent"
req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
resp = json.loads(urllib.request.urlopen(req, timeout=300).read())
print("".join(p.get("text", "") for p in resp["candidates"][0]["content"]["parts"]))
