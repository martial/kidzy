"""The 3D toy art of « Sketches for kids! » (Gemini 3 Pro Image on Vertex AI, project screen-club).

Usage:
  python3 -I ios/Tools/GenerateToyArt.py "$(gcloud auth print-access-token)" OUT_DIR [name ...]
  swiftc -O ios/Tools/Cutout.swift -o /tmp/cutout && /tmp/cutout OUT_DIR/toy-sea.png toy-sea-cut.png

The sailboat is generated first and becomes the style reference of every other toy, so the set
keeps one material, light and scale. Images come on white; Cutout.swift lifts the subject with
Vision. Existing files are kept: delete one to regenerate it. A new toy = one line in TOYS.
"""
import base64, json, os, sys, urllib.error, urllib.request

PROJECT = "screen-club"
MODEL = "gemini-3-pro-image"

STYLE = ("Chunky designer toy for toddlers, made of soft glossy vinyl, very rounded edges, cute playful proportions, "
         "vivid saturated candy colors, studio product photo with soft top light, gentle contact shadow, three-quarter view, "
         "centered with generous margin, plain pure white background, no text, no logo.")
SAME = ("Same style as the reference image: the same soft glossy vinyl designer-toy material, the same studio lighting and soft "
        "contact shadow, the same three-quarter view and scale, the same candy palette, centered with generous margin, plain pure "
        "white background, no text, no logo.")
ICON = ("Square app icon artwork filling the whole square edge to edge (no rounded corners, no border, no margin, no text): soft "
        "glossy 3D vinyl designer-toy render, vivid candy colors, studio lighting, same material and style as the reference toys.")

ANCHOR = ("toy-sea", "A little toy sailboat riding a small round splash of turquoise water: coral-red rounded hull with a yellow "
          "porthole, one big white triangular sail, a tiny yellow pennant flag on top, a couple of water droplets. " + STYLE)
TOYS = {
    "toy-paint": "A chunky toy paint palette with four glossy blobs of paint (coral red, sunny yellow, sky blue, leaf green) and a chunky paintbrush with a yellow handle whose tip is dipped in blue paint, a little swirl of mixed paint. " + SAME,
    "toy-tiles": "A playful little stack of chunky geometric toy blocks: a coral quarter-circle, a yellow triangle, a blue half-disc, a green square with a rounded corner and a violet arch, slightly tumbling. " + SAME,
    "toy-animals": "A cute sitting toy cow, white with a few black spots, pink snout, small rounded horns, big friendly black eyes with a white glint, a tiny smile, a little yellow bell on its collar. " + SAME,
    "toy-guitar": "A chunky little toy acoustic guitar in warm orange wood with a dark round sound hole ringed in yellow, six white strings, a short rounded neck with round tuning pegs, standing upright and slightly tilted. " + SAME,
    "toy-parrot": "A cute chubby toy scarlet macaw parrot standing, red body, blue and yellow wing feathers, white face patch, big friendly black eyes with a white glint, a chunky orange beak slightly open as if talking, little orange feet. " + SAME,
}
# the icon uses the parrot as its reference, at 2K
ICONS = {
    "icon-parrot": ("toy-parrot", ICON + " The cute toy scarlet macaw parrot from the reference, big and close, head and chest filling most of the square, slightly turned, beak open in a happy talk, on a warm sunny yellow-to-orange background with a soft glow."),
}


def generate(token, out, prompt, refs=(), size=None):
    if os.path.exists(out):
        print("have", os.path.basename(out))
        return
    parts = [{"inlineData": {"mimeType": "image/png", "data": base64.b64encode(open(r, "rb").read()).decode()}} for r in refs]
    parts.append({"text": prompt})
    image_config = {"aspectRatio": "1:1"}
    if size:
        image_config["imageSize"] = size
    body = {"contents": [{"role": "user", "parts": parts}],
            "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": image_config}}
    url = f"https://aiplatform.googleapis.com/v1/projects/{PROJECT}/locations/global/publishers/google/models/{MODEL}:generateContent"
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=240) as r:
            resp = json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"{os.path.basename(out)}: HTTP {e.code} {e.read()[:300]!r}")
    rparts = resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])
    data = next((p["inlineData"]["data"] for p in rparts if "inlineData" in p), None)
    if not data:
        sys.exit(f"{os.path.basename(out)}: no image in the response")
    open(out, "wb").write(base64.b64decode(data))
    print("wrote", os.path.basename(out))


def main():
    token, out_dir = sys.argv[1], sys.argv[2]
    wanted = set(sys.argv[3:])
    os.makedirs(out_dir, exist_ok=True)
    path = lambda name: os.path.join(out_dir, name + ".png")
    name, prompt = ANCHOR
    generate(token, path(name), prompt)
    for name, prompt in TOYS.items():
        if not wanted or name in wanted:
            generate(token, path(name), prompt, refs=[path(ANCHOR[0])])
    for name, (ref, prompt) in ICONS.items():
        if not wanted or name in wanted:
            generate(token, path(name), prompt, refs=[path(ref)], size="2K")


if __name__ == "__main__":
    main()
