// The App Store screenshots of « Sketches for kids! »: each capture from StoreMedia.py on its
// toy's cabinet colour (polka dots, as in the app), one line for parents above it in Baloo 2,
// in English, French, Spanish and Italian. 1320 x 2868, the 6.9-inch slot.
//
//   swift ios/Tools/FrameScreenshots.swift SHOTS_DIR OUT_DIR
//
// OUT_DIR gets en/, fr/, es/ and it/NN-name.png, numbered in store order.
import AppKit
import CoreText

struct Shot {
    let file: String
    let top: UInt32, bottom: UInt32   // the cubby colours of PickerView
    let text: [String: String]        // per language
}

let languages = ["en", "fr", "es", "it"]

let nb = "\u{00A0}"   // French puts a no-break space before a colon
let shots = [
    Shot(file: "paint", top: 0xFFA2C0, bottom: 0xFFCFDE,
         text: ["en": "Finger paint that mixes like real paint", "fr": "Peins au doigt, les couleurs se mélangent",
                "es": "Pinta con los dedos, los colores se mezclan", "it": "Dipingi con le dita, i colori si mescolano"]),
    Shot(file: "home", top: 0xFFC530, bottom: 0xFFD95C,
         text: ["en": "Six toys. Nothing to read, no ads", "fr": "Six jouets. Rien à lire, pas de pub",
                "es": "Seis juguetes. Nada que leer, sin anuncios", "it": "Sei giocattoli. Niente da leggere né pubblicità"]),
    Shot(file: "sea-sunset", top: 0x8FD3FF, bottom: 0xC6EAFF,
         text: ["en": "Tilt the sea, sail the boat, put the sun to bed", "fr": "Penche la mer, fais voguer le bateau",
                "es": "Inclina el mar, navega, acuesta al sol", "it": "Inclina il mare, fai navigare la barca"]),
    Shot(file: "guitar", top: 0x79D9CC, bottom: 0xB9EFE7,
         text: ["en": "Strum a real recorded guitar", "fr": "Gratte une vraie guitare enregistrée",
                "es": "Rasguea una guitarra grabada de verdad", "it": "Strimpella una vera chitarra registrata"]),
    Shot(file: "tiles", top: 0xB6A2FF, bottom: 0xDCD2FF,
         text: ["en": "Tap the shapes: marimba, bells, kalimba", "fr": "Des formes qui jouent marimba et clochettes",
                "es": "Formas que tocan marimba y campanitas", "it": "Forme che suonano marimba e campanelli"]),
    Shot(file: "parrot", top: 0xFFD45A, bottom: 0xFFEAA4,
         text: ["en": "The parrot repeats you in a silly voice", "fr": "Le perroquet te répète d’une drôle de voix",
                "es": "El loro te repite con una voz divertida", "it": "Il pappagallo ti ripete con una voce buffa"]),
    Shot(file: "animals", top: 0x8FDB7C, bottom: 0xC3EEB6,
         text: ["en": "Tap an animal: its name, then its cry", "fr": "Touche un animal\(nb): son nom, puis son cri",
                "es": "Toca un animal: su nombre, luego su sonido", "it": "Tocca un animale: il nome, poi il verso"]),
]

let width = 1320, height = 2868
let ink = CGColor(srgbRed: 0x1F / 255, green: 0x2A / 255, blue: 0x44 / 255, alpha: 1)

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// run from the repository or from ios/
let fontURL = ["ios/SketchesForKids/Resources/Fonts/Baloo2-ExtraBold.ttf", "SketchesForKids/Resources/Fonts/Baloo2-ExtraBold.ttf"]
    .map { URL(fileURLWithPath: $0) }
    .first { FileManager.default.fileExists(atPath: $0.path) } ?? URL(fileURLWithPath: "Baloo2-ExtraBold.ttf")
guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor], let baloo = descriptors.first else {
    fatalError("Baloo 2 not found at \(fontURL.path)")
}

/// The caption, centred, on at most two lines, the same size on every screenshot.
func caption(_ text: String, in gc: CGContext, box: CGRect) {
    let size: CGFloat = 100
    let font = CTFontCreateWithFontDescriptor(baloo, size, nil)
    let align = CTTextAlignment.center
    let lineHeight = size * 1.08
    let paragraph = withUnsafeBytes(of: align) { a in
        withUnsafeBytes(of: lineHeight) { h in
            let style = [
                CTParagraphStyleSetting(spec: .alignment, valueSize: a.count, value: a.baseAddress!),
                CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: h.count, value: h.baseAddress!),
                CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: h.count, value: h.baseAddress!),
            ]
            return CTParagraphStyleCreate(style, style.count)
        }
    }
    let attributes: [NSAttributedString.Key: Any] = [
        .init(kCTFontAttributeName as String): font,
        .init(kCTForegroundColorAttributeName as String): ink,
        .init(kCTParagraphStyleAttributeName as String): paragraph,
    ]
    let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: box.width, height: .greatestFiniteMagnitude), nil)
    let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: 0, y: 0, width: box.width, height: fit.height + 4), transform: nil), nil)
    guard CFArrayGetCount(CTFrameGetLines(frame)) <= 2, fit.height <= box.height else {
        fatalError("caption longer than two lines, shorten it: \(text)")
    }
    gc.saveGState()
    gc.translateBy(x: box.minX, y: box.midY - (fit.height + 4) / 2)
    CTFrameDraw(frame, gc)
    gc.restoreGState()
}

func render(_ shot: Shot, text: String, from dir: URL, to url: URL) throws {
    guard let image = NSImage(contentsOf: dir.appendingPathComponent(shot.file + ".png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "frame", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(shot.file).png"])
    }
    let gc = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!   // App Store Connect refuses screenshots with alpha
    // the wall: the cubby's gradient and soft white dots
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(shot.top), color(shot.bottom)] as CFArray, locations: [0, 1])!
    gc.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: 0, y: CGFloat(height) * 0.25), options: [.drawsAfterEndLocation])
    gc.setFillColor(CGColor(gray: 1, alpha: 0.32))
    var y: CGFloat = 46
    while y < CGFloat(height) {
        var x: CGFloat = 46
        while x < CGFloat(width) {
            gc.fillEllipse(in: CGRect(x: x - 8, y: y - 8, width: 16, height: 16))
            x += 96
        }
        y += 96
    }
    // the screen: a rounded sticker with an ink outline and a hard shadow under it
    let screenWidth: CGFloat = 1000
    let screenHeight = screenWidth * CGFloat(image.height) / CGFloat(image.width)
    let screen = CGRect(x: (CGFloat(width) - screenWidth) / 2, y: 96, width: screenWidth, height: screenHeight)
    let radius = screenWidth * 0.125
    let outline: CGFloat = 12
    let rim = CGPath(roundedRect: screen.insetBy(dx: -outline, dy: -outline), cornerWidth: radius + outline, cornerHeight: radius + outline, transform: nil)
    gc.saveGState()
    gc.translateBy(x: 0, y: -22)
    gc.addPath(rim)
    gc.setFillColor(ink.copy(alpha: 0.28)!)
    gc.fillPath()
    gc.restoreGState()
    gc.addPath(rim)
    gc.setFillColor(ink)
    gc.fillPath()
    gc.saveGState()
    gc.addPath(CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil))
    gc.clip()
    gc.interpolationQuality = .high
    gc.draw(image, in: screen)
    gc.restoreGState()
    // the line for parents, above
    let top = screen.maxY + outline
    caption(text, in: gc, box: CGRect(x: 90, y: top + 40, width: CGFloat(width) - 180, height: CGFloat(height) - top - 100))
    let png = NSBitmapImageRep(cgImage: gc.makeImage()!).representation(using: .png, properties: [:])!
    try png.write(to: url)
}

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: swift FrameScreenshots.swift SHOTS_DIR OUT_DIR")
    exit(2)
}
let source = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
for language in languages {
    let dir = out.appendingPathComponent(language)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (i, shot) in shots.enumerated() {
        let url = dir.appendingPathComponent(String(format: "%02d-%@.png", i + 1, shot.file))
        try render(shot, text: shot.text[language] ?? shot.text["en"]!, from: source, to: url)
        print(url.path)
    }
}
