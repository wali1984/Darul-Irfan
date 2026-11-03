# Urdu Akram-ut-Tarajum: spelling of لیے / لئے / لیئے set to the 2020 print

Scope: the word "for" (and the same word as the verb "liye", e.g. کاٹ لیئے) in
`akram-ut-tarajum-ur` rows of quran_translations.json, standalone or written
attached (کےلیئے, لیئےکہ). Only that word's spelling changed; no other word,
edition, spacing or Arabic text was touched. Authority: the 2020 complete
volume (Akram-ut-Tarajum-Parah-1-to-30-1.pdf), read by eye on 2026-11-03.

## What the print uses

The 2020 print is consistent but not uniform. Out of 1,309 occurrences:

| Printed form | Seen | Written in the app as |
|---|---|---|
| lam, one tooth with two dots below, hamza above, barree ye (لیۓ shape) | 1,272 | لیئے |
| lam, hamza on an undotted tooth, barree ye | 27 | لئے |
| lam, dotted tooth, no hamza, barree ye | 4 | لیے |

The dominant form, including 2:45, has both the hamza and the two dots of
the ye. Among the app's existing spellings, لیئے is the one that carries both.
The printed shape is closest to لیۓ (U+06D3), but that character was not
introduced. Crops are in `outputs/darul-design-review/lie-spelling/`.

## How it was checked

1. Each ayah was placed on its 2020 page using the 2012 per-page readings
   and the ORB page pairing (audit-2026-10-29/tarajum-2020/page_map.json).
2. Each word was found on the page by template matching inside the Urdu
   translation bands. Found words were matched to the app's occurrences in
   reading order, but only where the counts on the page cluster agreed.
3. Clusters where the counts disagreed (157 occurrences) were placed by
   hand from line-context crops: the surrounding words were read against
   the app text.
4. Every occurrence was rendered as a labelled tile (3x of the 300-dpi scan)
   and looked at:
   - 1,151 tiles were split among three visual reviewers, one third each.
   - The other 158 were read directly.
   - Every tile flagged as non-standard was re-read at 6x.
   - A dot and hamza detector also scanned all tiles. Every tile it marked
     as non-standard was looked at.

## Changes (821 tokens in 706 ayat)

| App spelling | New spelling | Count |
|---|---|---|
| لئے | لیئے | 691 |
| لیے | لیئے | 114 |
| لئیے | لیئے | 8 |
| لیے | لئے | 3 |
| لیئے | لئے | 3 |
| لئے | لیے | 2 |

The print's لئے and لیے spots:
- **لئے:** 4:90, 7:138, 7:155, 8:74, 9:38, 12:19, 16:13 (2nd), 20:75,
  20:77, 20:88, 20:109, 22:27, 23:19, 23:20 (1st), 24:61, 25:20, 25:22,
  25:39, 26:218, 41:48, 41:50 (1st), 42:13, 42:15 (1st), 42:27, 45:4,
  47:3 (2nd), 68:38.
- **لیے:** 27:5, 33:44, 40:43, 83:10.

After the change the edition has لیئے 1,273, لئے 32 and لیے 7 standalone.

## Left unchanged (needs the owner)

- **27:40, 27:41, 80:20:** the print joins the word as کیلیئے ("کیلئے" form).
  The app has کے لئے, so changing it would also change word division.
- **109:6 (both), 59:9:** the hamza spot is crowded by the next word's dots
  (تمہارا, میرا, بھی). The app keeps لئے / لیے / لیے.
- **Not checked:** forms attached after another letter (کرلئیے 100:10,
  کرلیے, بنالئے, پرہولئے). The imperative forms ڈالئے and چلئیے are other words.

## Gates

`check_content.py` PASS, `hadith_gate.py` PASS. The iOS and Android seeds
are byte-identical. Each changed row differs from HEAD only in this token.

## Follow-up, 3 November: the five spots left open (owner: "review and publish")

Re-read at 700-900 dpi from the 2020 volume, PDF pages 728, 1045, 1118 and 1149:

- **27:40, 27:41, 80:20:** the print joins the word to کے, with two dots below and a hamza, as **کیلیئے**. The app's کے لئے is now کیلیئے, matching the print's word division.
- **109:6, both occurrences:** the print uses the standard form with dots and hamza. لئے and لیے both became **لیئے**.
- **59:9:** the print shows dots below and no hamza at any zoom, so it stays **لیے**, one of the print's few plain forms.
- **ۓ (U+06D3):** not adopted. لیئے is how the app writes this printed shape everywhere. It renders the same in the app's Urdu fonts, and it keeps search consistent.
- Duas and Ayah of the Day were re-checked and none of their texts include these ayat.
