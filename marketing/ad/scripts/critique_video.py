"""Ask Gemini (Vertex, project screen-club) to watch the ad and critique it.
python3 -I critique_video.py TOKEN VIDEO.mp4 [model]"""
import base64, json, sys, urllib.request
token, video = sys.argv[1], sys.argv[2]
model = sys.argv[3] if len(sys.argv) > 3 else "gemini-3.1-pro-preview"
prompt = """You are the creative director of a top toy-commercial studio, reviewing a 20-second vertical Instagram ad (an animatic:
low resolution, final quality will be higher) for a kids' iPhone app "Sketches for kids!" (six toys: a sea with a boat, paint
that mixes like real paint, shapes that play marimba, animals, a guitar, a parrot). Concept "The toys break out": a finger taps the
phone, the parrot bursts out, water floods out with the boat, paint spirals out (blue + yellow = green), the guitar strums while
shapes rain down, the cow jumps out, three quick close-ups of the real app, a tornado sucks everything back in, end card.
The sound is built from the app's own sounds plus a placeholder music bed on the app's instruments (120 bpm).
Watch and listen. Be blunt and specific, with timestamps: what is confusing, too fast or too slow, ugly or amateur, where the energy
drops, where sound and picture don't match, what reads as fake. Then the 5 concrete changes that would most improve it. Under 400 words."""
body = {"contents": [{"role": "user", "parts": [{"inlineData": {"mimeType": "video/mp4", "data": base64.b64encode(open(video, "rb").read()).decode()}}, {"text": prompt}]}],
        "generationConfig": {"temperature": 0.4}}
url = f"https://aiplatform.googleapis.com/v1/projects/screen-club/locations/global/publishers/google/models/{model}:generateContent"
req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
resp = json.loads(urllib.request.urlopen(req, timeout=600).read())
print("".join(p.get("text", "") for p in resp["candidates"][0]["content"]["parts"]))
