"""Record the ad's phone screens on the real iPhone, smooth and with the app's sound.

    python3 -I scripts/record_phone.py [home sea paint guitar animals]

The iPhone must be plugged in over USB, unlocked (Auto-Lock: Never while recording) and trust this
Mac; the terminal needs the Camera permission once (that is how macOS sees an iPhone screen, as in
QuickTime). For each screen, StoreMediaUITests (ios/SketchesForKids/UITests) plays the toy on the
phone while ios/Tools/PhoneCapture.swift records the screen over USB. Recording starts only once the
test has launched the app, so nothing else on the phone is captured. Each take becomes
screens/<name>.mov at a steady 60 fps; then set the roles' `start` in screens.json and ./render.sh.
"""
import os, subprocess, sys, tempfile, time

AD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS = os.path.join(AD, "..", "..", "ios")
TESTS = {"home": "testHome", "sea": "testSea", "paint": "testPaint", "guitar": "testGuitar", "animals": "testAnimals"}
DERIVED = os.path.join(IOS, "build", "device-media")


def device_id():
    out = subprocess.run(["xcrun", "xctrace", "list", "devices"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "iPhone" in line and "Simulator" not in line and "(" in line:
            return line.rsplit("(", 1)[1].rstrip(")").strip()
    sys.exit("no iPhone found: plug it in over USB and unlock it")


def main():
    names = sys.argv[1:] or list(TESTS)
    work = tempfile.mkdtemp(prefix="ad-phone-")
    capture = os.path.join(work, "phonecapture")
    subprocess.run(["swiftc", "-O", os.path.join(IOS, "Tools", "PhoneCapture.swift"), "-o", capture], check=True)
    if subprocess.run([capture, "--list"]).returncode != 0:
        sys.exit("the Mac does not see the iPhone screen: USB cable, unlocked, trusted, Camera permission")
    dest = f"id={device_id()}"
    print("building the app and its UI tests for the phone")
    subprocess.run(["xcodebuild", "build-for-testing", "-project", "Kidzy.xcodeproj", "-scheme", "SketchesForKids",
                    "-destination", dest, "-derivedDataPath", DERIVED, "-allowProvisioningUpdates",
                    "DEVELOPMENT_TEAM=PC5K6NYDF2", "CODE_SIGN_STYLE=Automatic", "-quiet"], cwd=IOS, check=True)
    for name in names:
        raw, log = os.path.join(work, f"{name}.mov"), os.path.join(work, f"{name}.log")
        print(f"== {name}")
        env = dict(os.environ, TEST_RUNNER_STORE_MEDIA_OUT="device")
        xc = subprocess.Popen(["xcodebuild", "test-without-building", "-project", "Kidzy.xcodeproj", "-scheme", "SketchesForKids",
                               "-destination", dest, "-derivedDataPath", DERIVED,
                               f"-only-testing:SketchesForKidsUITests/StoreMediaUITests/{TESTS[name]}"],
                              cwd=IOS, env=env, stdout=open(log, "w"), stderr=subprocess.STDOUT)
        cap = None
        while xc.poll() is None:
            # once the app is up: starting at the launch itself loses the stream when the screen turns portrait
            if cap is None and "Wait for com.screenclub.sketchesforkids to idle" in open(log).read():
                cap = subprocess.Popen([capture, raw, "120"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(0.1)
        if cap:
            open(raw + ".stop", "w").close()
            cap.wait()
        if xc.returncode != 0 or not os.path.exists(raw):
            print(open(log).read()[-800:])
            sys.exit(f"{name}: the take failed (phone locked? see above)")
        length = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", raw],
                                      capture_output=True, text=True).stdout)
        # the last second can show the phone's home screen once the test closes the app
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-t", f"{max(length - 1.2, 0.5):.2f}", "-fps_mode", "cfr", "-r", "60",
                        "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
                        os.path.join(AD, "screens", f"{name}.mov")], check=True)
        os.remove(raw)
        print(f"screens/{name}.mov ({length - 0.8:.1f} s)")
    print("now set each role's start in screens.json (watch the clips), then ./render.sh")


if __name__ == "__main__":
    main()
