"""Ad art for « The toys break out »: 2K poses of the toy characters (Gemini 3 Pro Image, Vertex, project
screen-club), each from its existing toy art as reference so the characters stay identical.
Usage: python3 -I gen_art.py TOKEN OUT_DIR REFS_DIR [name ...]   (existing files are kept)"""
import base64, json, os, sys, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor

PROJECT, MODEL = "screen-club", "gemini-3-pro-image"
KEEP = ("Exactly the same character as the reference image: the same soft glossy vinyl designer-toy material, the same "
        "colours, proportions, eyes and details, rendered as a premium 3D toy product shot with soft studio light. ")
WHITE = (" Isolated on a plain pure white background, the whole character visible with a generous margin, no shadow on "
         "the background, no floor, no text, no logo.")
ASSETS = {
  # name: (refs, aspect, prompt)
  "parrot-burst": (["toy-parrot"], "1:1", KEEP + "Now bursting forward toward the camera with huge joy: both wings spread wide open, "
      "feathers fanned, beak wide open squawking happily, eyes sparkling, body leaning toward the viewer, seen slightly from below, very dynamic pose." + WHITE),
  "parrot-fly": (["toy-parrot"], "1:1", KEEP + "Now flying, seen from the side and a little below: wings raised high in a big flap, tail "
      "feathers streaming, feet tucked in, beak open in a happy call, energetic and joyful." + WHITE),
  "boat-surf": (["toy-sea"], "1:1", KEEP + "The little sailboat alone WITHOUT its round water base: only the coral hull with the yellow "
      "porthole, the big white sail and the yellow pennant, tilted about 20 degrees as if surfing fast down a wave, bow up, three-quarter view." + WHITE),
  "cow-jump": (["toy-animals"], "1:1", KEEP + "Now the cow is jumping for joy high in the air: all four legs stretched out like a star, body "
      "slightly stretched upward (cartoon squash and stretch), mouth wide open in a happy moo, eyes squeezed with delight, the yellow bell swinging." + WHITE),
  "guitar-strum": (["toy-guitar"], "2:3", KEEP + "Standing upright and slightly tilted, the six white strings vibrating with a visible "
      "motion blur shimmer as if just strummed, a few tiny sparkles near the sound hole." + WHITE),
  "palette-fly": (["toy-paint"], "1:1", KEEP + "The palette and its brush tumbling through the air, tilted dramatically, the glossy paint "
      "blobs bulging, a few drops of blue and yellow paint flying off the brush." + WHITE),
  "note": (["toy-parrot"], "1:1", "A chunky glossy vinyl toy musical note (an eighth note, ♪ shape) in sunny yellow with a soft white "
      "highlight, same toy material and studio light as the reference toy, three-quarter view." + WHITE),
  "hand": ([], "1:1", "Natural photo of a small child's hand (about four years old) seen from above at three-quarter, the index finger "
      "extended and slightly bent as if about to tap a phone screen, other fingers curled, cut at the wrist, soft daylight, natural skin, "
      "isolated on a plain pure white background, nothing else, no text."),
  "wood": ([], "1:1", "Seamless top-down photographic texture of a light natural oak tabletop: long planks running vertically, fine "
      "straight grain, satin finish, evenly lit with no shadows and no objects, high detail."),
  "kitchen": ([], "9:16", "A softly out-of-focus sunny modern family kitchen seen from a table, strong creamy bokeh: white cabinets, "
      "a big window with warm morning sun flaring in, green plants, a fruit bowl, pastel accents, no people, no text, warm cheerful light."),
}

def generate(token, out_dir, refs_dir, name):
    refs, aspect, prompt = ASSETS[name]
    out = os.path.join(out_dir, name + ".png")
    if os.path.exists(out):
        return f"have {name}"
    parts = [{"inlineData": {"mimeType": "image/png", "data": base64.b64encode(open(os.path.join(refs_dir, r + ".png"), "rb").read()).decode()}} for r in refs]
    parts.append({"text": prompt})
    body = {"contents": [{"role": "user", "parts": parts}],
            "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": aspect, "imageSize": "2K"}}}
    url = f"https://aiplatform.googleapis.com/v1/projects/{PROJECT}/locations/global/publishers/google/models/{MODEL}:generateContent"
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            resp = json.loads(r.read())
    except urllib.error.HTTPError as e:
        return f"{name}: HTTP {e.code} {e.read()[:200]!r}"
    rparts = resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])
    data = next((p["inlineData"]["data"] for p in rparts if "inlineData" in p), None)
    if not data:
        return f"{name}: no image ({json.dumps(resp)[:200]})"
    open(out, "wb").write(base64.b64decode(data))
    return f"wrote {name}"

if __name__ == "__main__":
    token, out_dir, refs_dir = sys.argv[1:4]
    names = sys.argv[4:] or list(ASSETS)
    os.makedirs(out_dir, exist_ok=True)
    with ThreadPoolExecutor(5) as ex:
        for msg in ex.map(lambda n: generate(token, out_dir, refs_dir, n), names):
            print(msg, flush=True)
