# Akram-ut-Tafaseer per-ayah rows re-cut from Claude's reading (2026-11-09)

Claude read Parahs 11-30 again on 8 November (seeds 57). The per-ayah rows of
surahs 10-91 are now cut from that text. Surahs 1-9 and 92-114 were already cut
from Claude's reading and reviewed by eye; their rows are kept exactly as they
shipped, including the hand fixes of 3 November.

What was done, and how it was checked:

- **Section corrections (SECTION_CORRECTIONS, KEPT_SURAH_CORRECTIONS):** 109 of
  the 452 reviewed cuts named words the new text no longer has (Surya's misreadings,
  such as "سورۃ الکعب رگو"). Each was re-anchored at the same place: the reviewed
  row's first words were found in the new text near the same point, a section's
  heading opening its own row. Ten cuts were set by hand (20:72, 22:20, 26:34,
  33:39, 40:79, 49:12, 68:2, 73:20, 89:27, 89:28). All 453 now apply.
- **Reviewed boundaries (REVIEWED_BOUNDARIES):** of the boundaries the earlier,
  shipped cut had and the new one moved, 1,356 landed in the same place. 175 moved
  onto a section heading or a sub-heading and were kept. 93 were set back to the
  shipped place, and 11 more set where a page split had opened a row with the
  previous ayah's quotation. Seven proposed ones were left out because the shipped
  place itself was wrong (12:92, 30:30, 37:154, 44:3, 44:6, 54:22, 83:11).
- **Headings:** a section heading left inside an earlier row now opens its own
  row (26 places). Section headings left inside earlier rows: 6 before, 0 now.
- **Sentences split across rows:** a cut inside a sentence moves back to the end
  of the previous sentence (44 places). Boundaries without a sentence end: 32
  before, 24 now, all of them before a quotation, a heading or after a closing
  du'a.
- Words and their order never change: every step checks this or only moves whole
  text between neighbouring rows.

Result: 3,484 rows, all 6,236 ayat covered, no row over the size limit, and no
row whose commentary quotes three or more earlier ayat (`misfiled`). Rows of
surahs 10-91 that open with a quotation of their own ayah: 1,588 before, 1,818 now;
rows that open with their section heading: 99 before, 268 now.

`verify_akram_rows.py` flags 305 rows (8.7%; 133 before). 294 of them open with
their section heading, whose opening recites every ayah of the section; that is
the same pattern as the 115 rows it flags in the reviewed surahs 1-9.

## Follow-up, 2026-11-10

- The 3 November corrections (nine word fixes in 2:103, 2:130, 3:106, 6:110, 7:8,
  7:56, 7:105 and 7:159) are now HAND_FIXES in the tool, applied last, so
  `segment_akram_tafaseer.py --write` reproduces the shipped rows byte for byte:
  no surahs need restoring by hand after a run.
- `verify_akram_rows.py` leaves out a section's opening recitation (its heading,
  then the Arabic of ayat a..b up to the marker of b). It now flags 23 rows
  (0.66%), under its 5% gate; 3,800 opening recitations are left out.
