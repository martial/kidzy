# « Sketches for kids! » — App Store Connect, everything to paste

Bundle id `com.screenclub.sketchesforkids` · SKU `sketches-for-kids` · primary language **English (U.S.)**,
localization **French**. Kids Category, age band **5 and under** (« Made for Kids », irreversible once
approved). Free app with one non-consumable in-app purchase. Privacy: **« No, we do not collect data »**
→ label « Data Not Collected » (the parrot's audio is processed on device only).

Pages (GitHub Pages from `docs/`, branch `main`): privacy
https://martial.github.io/kidzy/sketches/privacy.html · support https://martial.github.io/kidzy/sketches/support.html

## App (version 1.0.0)

| Field | English | Français |
|---|---|---|
| Name (30) | Sketches for kids! | Sketches for kids! |
| Subtitle (30) | Six toys that play with you | Six jouets qui jouent avec toi |
| Promotional text (170) | A sea that sloshes when you tilt, paint that swirls under your fingers, animals, a guitar and a parrot that repeats you in a silly voice. No ads, no text, nothing to read. | Une mer qui bouge quand on penche, de la peinture qui tourbillonne sous les doigts, des animaux, une guitare et un perroquet qui te répète avec une voix rigolote. Sans pub, sans texte. |
| Keywords (100) | toddler,kids,toy,baby,sea,paint,parrot,guitar,animals,sticker,play,preschool | tout-petit,enfant,jouet,bébé,mer,peinture,perroquet,guitare,animaux,jeu,maternelle |
| Support URL | https://martial.github.io/kidzy/sketches/support.html | same |
| Marketing URL | (none) | |
| Privacy policy URL | https://martial.github.io/kidzy/sketches/privacy.html | same |
| Copyright | 2026 Martial Geoffre-Rouland | |
| Category | Kids (primary) · Education or Entertainment (secondary) | |

**Description (EN)**

Sketches for kids! is a box of six toys for little hands, with nothing to read and nothing to buy by accident.

• The sea: tilt the phone and the water sloshes; a little boat slides, bobs and can be dragged. Tap the water for a splash, tap the sun to make it giggle, drag it down for a sunset and a starry night.
• Paint: lay the phone on the table and swirl bright colours with your fingers; they mix like wet paint and sing a gentle note for each finger.
• Shapes: a grid of coloured tiles that turn when you tap them, making ever-changing patterns.
• Animals: ten friendly stickers; tap one to hear its name and its cry.
• Guitar: strum six strings, pick a chord sticker, the sky changes colour with the mood.
• Parrot: say something, stop, and the parrot repeats it in a silly voice.

The sea and the animals are free. One purchase, « All toys », unlocks the other four, forever, behind a question for parents. No ads, no accounts, no data collected. The parrot listens on the phone only; nothing is recorded or sent.

To leave a toy, tap the house sticker. Parents: the gate (a sum) opens the settings, where any toy can be hidden.

**Description (FR)**

Sketches for kids! est une boîte de six jouets pour les petites mains, sans rien à lire et sans rien à acheter par accident.

• La mer : penche le téléphone et l'eau bouge ; un petit bateau glisse, flotte et se laisse tirer. Touche l'eau pour une éclaboussure, touche le soleil pour le faire rire, descends-le pour un coucher de soleil et une nuit étoilée.
• Peinture : pose le téléphone sur la table et fais tourbillonner des couleurs vives avec les doigts ; elles se mélangent comme de la peinture fraîche et chantent une note par doigt.
• Formes : une grille de tuiles colorées qui tournent quand on les touche, pour des motifs toujours nouveaux.
• Animaux : dix autocollants rigolos ; touche-en un pour entendre son nom et son cri.
• Guitare : gratte six cordes, choisis un accord, le ciel change de couleur avec l'humeur.
• Perroquet : dis quelque chose, arrête-toi, et le perroquet te répète avec une voix rigolote.

La mer et les animaux sont gratuits. Un seul achat, « Tous les jouets », débloque les quatre autres, pour toujours, derrière une question réservée aux parents. Sans pub, sans compte, sans collecte de données. Le perroquet écoute sur le téléphone seulement ; rien n'est enregistré ni envoyé.

Pour sortir d'un jouet, touche l'autocollant maison. Parents : la porte (une addition) ouvre les réglages, où chaque jouet peut être masqué.

**Review notes (EN, paste in « Notes »)**

Made for kids, age 5 and under. No account, no network, no third-party SDK, no analytics, no ads.
Parental gate: the person sticker (top right of the home screen) and every locked toy ask a sum of two
digits (e.g. "What is 7 + 5?"); type the answer on the keypad. The gate precedes the in-app purchase,
the settings and the two links (privacy policy, support e-mail). The in-app purchase "All toys"
(com.screenclub.sketchesforkids.alltoys) unlocks Paint, Shapes, Guitar and Parrot; restore is on the
same page. Microphone: used only by the Parrot toy, on device, to repeat the child's phrase in a
pitched voice; audio stays in memory for a few seconds and is never stored or transmitted; an ear
sticker pulses while the microphone is on. To leave a toy, tap the house sticker at the top left.

## In-app purchase (create before submitting; it must ship with version 1.0)

| Field | Value |
|---|---|
| Type | Non-consumable |
| Reference name (64) | All toys |
| Product ID | `com.screenclub.sketchesforkids.alltoys` (never reusable after save) |
| Price | base country France, **2,99 €** (price point; the other storefronts follow) |
| Family Sharing | on |
| Display name EN (30) | All toys |
| Description EN (45) | Paint, Shapes, Guitar and Parrot |
| Display name FR (30) | Tous les jouets |
| Description FR (45) | Peinture, Formes, Guitare et Perroquet |
| Review screenshot | the unlock page (`ios/scripts/screenshots.sh` makes `store/unlock.png`, 1290×2796) |
| Review notes | Reached from a locked toy on the home screen after the parental gate (a sum). |

Before all that: Agreements → the **Paid Apps Agreement** must be accepted by the Account Holder, with
banking and tax forms, or the IAP cannot be priced.

## Age rating questionnaire

All « None » (no violence, no gambling, no mature themes, no unrestricted web access, no contests),
then **Age Categories and Override → Made for Kids → 5 and under**.

## App privacy

« No, we do not collect data from this app. » Microphone audio is processed on device and never
leaves it, which Apple defines as not collected.

## Screenshots

`ios/scripts/screenshots.sh` produces the 6.7″ set (1290×2796) from the simulator: the picker, the
sea, paint, animals, guitar, parrot, and the unlock page for the IAP review. Captions, if any, go on
the images later; the app itself shows no text.

## Order of operations

1. Paid Apps Agreement (Account Holder).
2. Apps → + → New App: iOS, name « Sketches for kids! », primary language English (U.S.), bundle id
   `com.screenclub.sketchesforkids` (register it in Identifiers if it is not offered), SKU `sketches-for-kids`.
3. Monetization → In-App Purchases → + → Non-Consumable: the table above, price, both localizations,
   the review screenshot.
4. App Information: category Kids, privacy policy URL; App Privacy: no data; Age Rating: Made for Kids.
5. Version 1.0: texts above (EN then FR), screenshots, « Sign-in required: no », the IAP added to the
   version under « In-App Purchases and Subscriptions », build from TestFlight, review notes.
6. Submit.
