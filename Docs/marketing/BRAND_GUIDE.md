# Brand Guide — Darul Irfan

The brand system for Darul Irfan, the official companion of **Silsila
Naqshbandia Owaisiah** (Dar-ul-Irfan, Munara, District Chakwal, Pakistan). It
exists to make every surface — app, store, and communication — feel reverent,
scholarly, warm and unmistakably premium. Colour and type tokens here match the
shipping design system (`DarulIrfanApp/Core/DesignSystem/Theme.swift`,
`Ornaments.swift`).

---

## 1. Name & wordmark

- **Name:** **Darul Irfan** (two words, both capitalised). "Darul Irfan" — the
  House of Gnosis / of spiritual knowledge.
- **Urdu:** **دارالعرفان** (one word in Urdu). Always set in Noto Nastaliq Urdu.
- **Never:** "DarulIrfan", "Dar-ul-Irfan" *(as the app name)*, "DI", "Darul
  Irfaan", all-caps "DARUL IRFAN" in body text, or a translated app name.
  - Exception: **Dar-ul-Irfan** (hyphenated) is correct when referring to the
    **physical headquarters / Munara**, not the app.
- **Wordmark lockup:** the word "Darul Irfan" in the serif heading face, optical
  kerning, ink or emerald; may sit to the right of the seal (see §3). Keep clear
  space around the lockup equal to the height of the "D".
- **Attribution line** (use where space allows): *"The official app of Silsila
  Naqshbandia Owaisiah."*

---

## 2. Tagline & anchor verse

- **Primary tagline:** **"Exploring the Treasures of the Heart"**
  - Urdu: **دل کے خزانوں کی تلاش**
- **Secondary / launch subtitle (optional):** "Light of Sacred Knowledge" —
  *(carry-over line; use sparingly, never in the same lockup as the primary
  tagline)*.
- **Anchor verse — the spiritual signature (Qur'an 13:28):**
  - Arabic: **اَلَا بِذِكْرِ اللّٰهِ تَطْمَئِنُّ الْقُلُوْبُ**
  - English (Akram-ut-Tarajum): *"Remember! Only in Allah’s Zikr do hearts find satisfaction."*
  - Urdu (Akram-ut-Tarajum): *"یاد رکھو! اللہ کے ذکر سے ہی دل اطمینان پاتے ہیں۔"*
  - Reference: **Qur'an 13:28**
  - Use it on splash, home headers, the press kit, and hero marketing — it is the
    emotional through-line of the entire product. Always give the reference
    ("Qur'an 13:28") and keep the Arabic verbatim.

---

## 3. The seal & octagram motif

The signature ornament is an **8-point Naqshbandi octagram** (a star-knot of two
overlaid squares), drawn from the pierced *jali* lattice of the Dar-ul-Irfan
Munara. It is the visual thread that makes the app read as an authentic
extension of the Silsila rather than a generic azan app.

- **Seal emblem:** a single octagram, often inside a fine ring, used as the app's
  emblem and as a section flourish. Gold on emerald, or emerald on cream.
- **Jali divider:** a low, thin band of repeating octagrams as a section divider
  or card-header trim — gold, low opacity ("a whisper, not a shout").
- **Watermark:** one large octagram at 4–8% opacity as a corner watermark on hero
  cards and screenshots.

**Motif rules**
- Prefer **one** octagram per surface as a focal mark; use the repeating band
  only as trim.
- Keep it geometric and precise — never rotate to a jaunty angle, never fill with
  gradients, never combine with unrelated iconography.
- Do not substitute a generic mosque, crescent, or dome as the primary emblem;
  the octagram is the mark.

---

## 4. Colour tokens

| Token | Hex | Role |
|---|---|---|
| **Emerald** | `#0B6E4F` | Primary brand colour; hero surfaces, primary buttons, active state |
| **Forest** | `#06432F` | Deep shade; gradients, dark surfaces, depth |
| **Gold** | `#C6A253` | Sacred accent; seal, dividers, ayah/verse highlights, kickers |
| **Cream** | `#F6F4EF` | App background / light reading surface; text on dark |
| **Charcoal ink** | `#1D1C1C` | Primary text; dark-mode surfaces; Qibla backdrop |
| **Crimson (Al-Murshid)** | `#B01E1E` | Reserved accent for Al-Murshid TV / live media only |

**Supporting tints (from the design system, for reference):** emerald tint
`#1E9068`, gold glow `#E0B75F` / `#FBCE54`, muted ink `#6B6357`, warm border
`#E4D9C6`.

**Usage**
- Emerald + cream + gold is the core triad. Emerald leads, cream carries reading,
  gold anoints (verses, seal, dividers) — never as large fills.
- **Crimson is quarantined** to Al-Murshid/live-media contexts. It must not appear
  on prayer, Qur'an, or general UI.
- Maintain WCAG AA contrast: ink/emerald on cream; cream on emerald/forest. Never
  gold text on cream for body copy (decorative accents only).
- Both light and dark modes ship; verify gold and crimson on the dark charcoal
  surface.

---

## 5. Typography

| Script | Face | Use |
|---|---|---|
| **Arabic (Qur'an)** | **IndoPak script** (bundled) | All Qur'anic Arabic — the mushaf reading face |
| **Arabic (other)** | **Amiri Quran** (bundled) | Arabic du'as and devotional prose |
| **Urdu** | **Noto Nastaliq Urdu** (Apple's, on the device) | All Urdu — wordmark, titles, body, captions; always RTL |
| **Headings (Latin)** | **Serif** (the app's serif heading face) | English titles, taglines, marketing headlines — scholarly, calm |
| **Body / UI (Latin)** | **SF Pro / system** | English body, controls, numerals; scales with Dynamic Type |

**Rules**
- Arabic Qur'anic text is **only ever** set in the bundled IndoPak face — never
  the system Arabic face, never a display font.
- Urdu is always Nastaliq and right-to-left; never force Urdu into a Latin face or
  LTR layout.
- Generous line-height for Arabic/Urdu; never tighten to fit.
- All text must support Dynamic Type and RTL. Never bake text into images except
  in marketing captions.
- Numerals: Western digits (0-9) in both English and Urdu, verse references
  included. The Qur'an's own Arabic is never altered.

---

## 6. Tone of voice

Reverent, scholarly, warm — the register of a trusted teacher, not a marketer.

- **Reverent:** dignified and unhurried. No hype, no exclamation-stacking, no
  urgency ("Download now!!"). Let the content's weight speak.
- **Scholarly & precise:** never paraphrase Qur'an, hadith, zikr instructions, or
  the Sheikh's words. Copy says nothing about how the text was produced or
  checked, and gives no credit lines.
- **Warm & inclusive:** welcoming to every Muslim and open-hearted seeker; "a
  gift to the community." Gentle, never shaming (mirrors the no-shame prayer
  tracker).
- **Honorifics — always observe:**
  - The Prophet Muhammad **ﷺ** (or "peace be upon him").
  - Present Sheikh: **Hazrat Ameer Abdul Qadeer Awan (MZA)** — *mudda zilluhu'l-aali*.
  - Late Sheikh: **Hazrat Ameer Muhammad Akram Awan (RA)** — *rahmatullah alayh*.
  - Companions/saints: (RA) as appropriate. Allah: "Allah", or "Allah ﷻ" /
    "Almighty Allah" where fitting.
- **Openings/closings** may use "Assalamu alaikum", "InshaAllah", "may it be a
  means of barakah", "we welcome your du'as" — sincerely, not as decoration.
- **Language:** clean, plain English and correct Urdu. Prefer "prayer times" and
  "adhan/azan", "du'a", "dhikr/zikr", "tasawwuf", "bay'at", "Silsila" — spelled
  consistently.

---

## 7. Voice — words we use / avoid

**Use:** official companion, Silsila Naqshbandia Owaisiah, complete,
offline, private, reverent, the Sheikh's works, calm, barakah, remembrance,
accurate prayer times.

**Avoid:** "best azan app ever", "#1", "revolutionary", "unlimited",
growth-hacky urgency, emojis in reverent copy, "no accounts", "no chat",
"location never leaves the device", any claim of a feature not shipping, and
anything that could read as issuing a religious ruling.

---

## 8. Dos & Don'ts (quick reference)

**Do**
- Lead with the twin identity: *accurate offline azan* **and** *official Silsila
  companion with the complete Qur'an*.
- Use the octagram seal, emerald/cream/gold triad, and IndoPak / Nastaliq
  faces faithfully.
- Keep all religious content verbatim.
- Observe honorifics every time a Sheikh or the Prophet ﷺ is named.
- Describe the books and tafsir as **read in the app as text**, with the PDF as
  an option, and Akram-ut-Tarajum as the Qur'an reader's translation.

**Don't**
- Don't call it "just" a prayer app, or compare on price/gimmicks.
- Don't overstate: no invented features, no exaggerated numbers, no claim that the
  app answers religious questions.
- Don't misuse crimson outside Al-Murshid/live media.
- Don't set Qur'anic Arabic in anything but the IndoPak face, or Urdu in a Latin face.
- Don't use flashy gradients, noisy animation, ad-style CTAs, or stock
  "lifestyle" imagery.
- Don't alter the seal geometry, tilt it, or swap it for a generic crescent/mosque.
