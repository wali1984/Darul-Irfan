# Screenshots Plan — Darul Irfan

A shot list for the App Store, plus device-frame and caption styling that keeps
every screenshot on-brand (emerald / gold / charcoal). Captions are short,
benefit-led, and given in **English and Urdu**.

## Required device classes (App is Universal: `TARGETED_DEVICE_FAMILY 1,2`)

| Class | Portrait canvas | Status |
|---|---|---|
| iPhone 6.9" (Pro Max) | 1290 × 2796 px | **Mandatory** |
| iPad Pro 13" | 2064 × 2752 px | **Mandatory** (app installs on iPad) |
| iPhone 6.5" | 1242 × 2688 px | Optional; Apple can down-scale the 6.9" set |

Produce the **same 8 shots** for iPhone 6.9" and iPad 13". On iPad, favour the
wider layouts (two-column reader, month timetable grid, split library) so the
tablet screenshots don't look like blown-up phone shots. Localise a full **Urdu
(RTL)** set in addition to the English set — for the Urdu set, mirror the frame
(caption right-aligned, device mirrored where the UI mirrors).

---

## Content & rights rule (read before capturing)

- **Qur'an Arabic + Pickthall/Jalandhry** and the **99 Names / du'as** are public
  domain or verbatim-licensed — safe to show in full.
- **Site article/page body text, lecture titles, publication listings** may
  appear — the content owner granted permission (2026-07-10); keep the written
  confirmation on file, and keep any religious text **verbatim** (no crops that
  distort meaning). See `Docs/APP_STORE_CHECKLIST.md` §3.
- Do **not** fabricate content in a screenshot. Use the app's real seeded data.
- Use a clean device state: real city (e.g. Chakwal or the reviewer's city),
  plausible next-prayer countdown, no debug banners, full status bar
  (9:41, full signal/battery).
- Do not use third-party video frames as marketing artwork. Live Activity and
  Watch screenshots may be added only from the signed, device-validated build.

---

## The 8 shots

### 1 — Prayer dashboard (hero)
- **Screen:** Prayer tab home — next-prayer hero with live countdown, today's six
  times, Hijri + Gregorian date, alert bells.
- **Caption EN:** *Accurate prayer times, fully offline.*
- **Caption UR:** *درست اوقاتِ نماز، مکمل آف لائن۔*
- **Notes:** The signature opener. Show a mid-day state so a real countdown reads
  (e.g. "Asr in 1:24"). Emerald hero card, gold hairline, octagram watermark
  faint in the corner. iPad: show the hero plus the week strip side-by-side.

### 2 — The complete Qur'an
- **Screen:** Surah reader on **Al-Fatihah** (or Al-Ikhlas 112) — Arabic in the
  Amiri Quran face with Pickthall English beneath; translation toggle visible.
- **Caption EN:** *The complete Qur'an — 114 surahs, verified, offline.*
- **Caption UR:** *مکمل قرآن — ۱۱۴ سورتیں، تصدیق شدہ، آف لائن۔*
- **Notes:** This is the headline differentiator vs. generic azan apps. Cream
  reading surface, generous line spacing, mushaf typography front and centre.
  iPad: two-column — Arabic column + translation column.

### 3 — Today (daily companion)
- **Screen:** Today tab — the daily ayah card, plus du'a / Name of Allah / dhikr
  / Aqwal-e-Sheikh cards; a visible **Share** affordance.
- **Caption EN:** *A verse, a du'a, a remembrance — every day.*
- **Caption UR:** *ایک آیت، ایک دعا، ایک ذکر — ہر روز۔*
- **Notes:** Warmth shot. Optionally place one branded **share card** floating to
  hint the share feature. Keep the Aqwal-e-Sheikh attribution line legible.

### 4 — Explore by topic
- **Screen:** Topics browse grid (Remembrance, Patience, Gratitude, Love of the
  Prophet ﷺ, Tasawwuf…) or a topic detail showing linked ayat + library.
- **Caption EN:** *Study the Qur'an by theme — ayat, books and bayans linked.*
- **Caption UR:** *قرآن کو موضوع کے اعتبار سے پڑھیں — آیات، کتب اور بیانات یکجا۔*
- **Notes:** Shows the cross-linking that no commodity prayer app offers. Gold
  topic icons on cream cards; keep the grid calm (2 columns).

### 5 — Qibla compass
- **Screen:** Qibla tab — compass pointing to the Ka'bah, degrees to true north,
  aligned/locked state (not the calibration warning).
- **Caption EN:** *Find the Qibla, wherever you are.*
- **Caption UR:** *جہاں کہیں بھی ہوں، قبلہ رخ معلوم کریں۔*
- **Notes:** Dark charcoal backdrop makes the emerald/gold needle glow. Show a
  clean "aligned" moment. Ka'bah glyph in gold.

### 6 — Bayans & Al-Murshid
- **Screen:** Media tab — audio lecture list (real Urdu titles + speaker + date)
  with the mini-player / Now Playing showing speed control and Lock Screen-style
  controls; Al-Murshid TV card visible.
- **Caption EN:** *Bayans of the Sheikh — listen offline, at your pace.*
- **Caption UR:** *مشائخ کے بیانات — آف لائن سنیں، اپنی رفتار سے۔*
- **Notes:** Nastaliq titles must render correctly in RTL. Show the 0.75×–2×
  speed pill and a download glyph to signal offline listening. Audio only.

### 7 — Naqshbandia Owaisiah library
- **Screen:** Library — category browser or an article reader in full verbatim
  text (an About page or article), with the works catalogue
  (Asrar-at-Tanzil / Akram-ut-Tafaseer / books) visible in a section.
- **Caption EN:** *The Silsila's library and the Sheikh's works — in your hand.*
- **Caption UR:** *سلسلہ کی لائبریری اور مشائخ کی تصانیف — آپ کے ہاتھ میں۔*
- **Notes:** Reader shot conveys "reference app," not "timer." RTL for Urdu
  articles. Keep the source/"Read on naqshbandiaowaisiah.org" link subtle.

### 8 — Privacy & widgets (closer)
- **Screen:** Split idea — the **Next Prayer widget** on a Home/Lock Screen
  mock **or** the Privacy settings screen ("No ads. No trackers. No accounts.").
  Pick one; if the store set allows 8, the widget reads more visually.
- **Caption EN (widget):** *Your next prayer, on your Home Screen.*
- **Caption UR (widget):** *آپ کی اگلی نماز، ہوم اسکرین پر۔*
- **Caption EN (privacy):** *No ads. No trackers. No accounts. Ever.*
- **Caption UR (privacy):** *نہ اشتہار، نہ ٹریکر، نہ اکاؤنٹ — کبھی نہیں۔*
- **Notes:** Closing trust note. If widget: show Next Prayer (small) + a Lock
  Screen circular so both families are advertised.

> Optional 9th (if a slot remains / for the 6.5" set): **Monthly timetable** with
> month navigation and share — Caption EN *"A month of prayer times, ready to
> share."* / UR *"پورے مہینے کے اوقاتِ نماز، شیئر کے لیے تیار۔"*

---

## Ordering strategy

Lead with **1 (Prayer)** and **2 (Qur'an)** — the two searches that bring people
in, and the pairing that states "this is more than an azan app" in the first
two thumbnails. Follow with **3 (Today)** and **4 (Topics)** for emotional pull
and the differentiator, then the utility/depth shots **5–8**.

---

## Device-frame & caption style guide

**Canvas / background**
- Full-bleed brand gradient behind the framed device: **forest #06432F → emerald
  #0B6E4F**, top-to-bottom, kept dark and calm (no rainbow gradients).
- A **very faint gold octagram** watermark (the app's 8-point Naqshbandi seal
  motif) bottom-corner at ~6–8% opacity. One motif, low, quiet.
- Consistent ~10–12% side margins so the device never touches the edge.

**Device frame**
- Realistic titanium/graphite iPhone and iPad frames, subtle soft shadow, no tilt
  on shots 1–4 (straight, authoritative); a gentle tilt is acceptable on utility
  shots 5–8 for variety. Keep angle consistent within each pair.

**Caption typography**
- Caption sits **above** the device (upper ~22% of the canvas).
- Headline: an elegant **serif** (matches the app's serif headings), **cream
  #F6F4EF** on the dark gradient, ~64–76 pt on 6.9". One line ideally, two max.
- Optional gold **eyebrow** word/kicker above the caption (e.g. "OFFLINE",
  "COMPLETE QUR'AN") in **gold #C6A253**, small caps, letter-spaced.
- A short **gold hairline or single octagram** between eyebrow and caption as a
  divider — the same trim used in-app (`DIJaliDivider`).
- Urdu set: caption in **Noto Nastaliq Urdu**, right-aligned, slightly larger
  line-height; mirror the layout (caption block right, device drift left).

**Colour tokens (keep exact)**
| Token | Hex | Use |
|---|---|---|
| Emerald | `#0B6E4F` | gradient base, needle |
| Forest | `#06432F` | gradient top, depth |
| Gold | `#C6A253` | eyebrow, hairline, octagram, accents |
| Cream | `#F6F4EF` | caption text, light surfaces |
| Charcoal ink | `#1D1C1C` | Qibla backdrop, dark captions on light |
| Crimson (Al-Murshid) | `#B01E1E` | **only** on the Media/Al-Murshid shot as a small live accent |

**Do**
- Keep one visual system across all 8 — same gradient, same caption position,
  same frame. The set should read as one family.
- Let whitespace breathe; reverent, not busy.
- Keep religious text crisp and legible; screenshot at native resolution.

**Don't**
- No flashy gradients, drop-shadow text, emoji, or "lifestyle" stock imagery.
- No countdown/badge numbers that imply features the app lacks.
- Don't crop Qur'anic or scholarly text mid-meaning.
- Don't show the crimson Al-Murshid accent anywhere except the Media shot.
