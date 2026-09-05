# Print Cloud — print quality troubleshooting

Reference for the **Print quality** drawer in the Label Designer, the settings it
talks about, and the faults it names. Written after a live session on the
GroTap/Manor View B-EX6T1 (2026-09-05) in which "the print quality is not
working across the entire label" turned out to be three separate problems
wearing one coat.

Sources, kept distinct on purpose:

| Source | What it covers |
|---|---|
| [Specialty Tag & Label, "Tech Tip Tuesday"](https://specialtytag.com/tech-tip-tuesday/) | The supplier's own troubleshooting videos for horticultural tag printers |
| Toshiba B-EX manual | Already shipped in the **Printer reference** drawer (`PrinterManualPanels.tsx`) |
| Our own hardware | Faults reproduced on the B-EX6T1 at `192.168.86.29` |

The UI names the source per symptom. Do not let ours borrow the supplier's
authority, or the reverse: inventing printer strings is a mistake this feature
has made before.

---

## The controls, and what they actually do

### Darkness

Called **tone** on TPCL and **darkness** on ZPL, and the two languages do not
share a range:

| Language | Range | Compiler constant |
|---|---|---|
| TPCL | `0 … 10` | `_TPCL_TONE_RANGE` |
| ZPL | `-30 … 30` | `_ZPL_DARKNESS_RANGE` |

Both live in `backend/app/services/label_compiler.py`. Anything outside the
range is **clamped during compilation**, so a value the printer will not honour
is not an error — it is a control that quietly does nothing.

Until 2026-09-05 the designer offered `0 … 30` for every printer. On a TPCL
printer that meant everything above 10 was discarded in silence: turn Darkness
from 10 to 25, print, and nothing changes, with no hint why. `RFID Label V1` was
sitting at Darkness 10 — already the maximum — while the operator was trying to
turn it up.

The range now follows the selected printer's language
(`frontend/src/pages/print-cloud/print-quality-guide.ts`, `DENSITY_RANGES`), and
the designer says so when the knob is on a rail. `backend/tests/test_print_quality_ranges.py`
pins the TypeScript table to the Python constants, because nothing else keeps
two copies of the same numbers in step.

**Direction rule** (Specialty Tag, "Poor Print Quality"):

- print **faint** → temperature is too **low** → raise Darkness
- print **blurry / smeared** → temperature is too **high** → lower Darkness

### Speed

Inches per second, `2 … 12`, both languages. A slower pass holds each dot under
the head longer, so lowering Speed prints darker at the same temperature. It is
the lever to reach for once Darkness is at its maximum and the print is still
faint.

### Stock and ribbon

`thermal_transfer` (a ribbon is loaded and its take-up motor is driven) or
`direct_thermal` (heat-sensitive paper, no ribbon). This cannot be sensed — no
printer reports which stock someone loaded — and getting it wrong is not a
nuance. Telling a printer with a ribbon fitted to run direct thermal leaves the
take-up idle, so the ribbon is dragged out of the front of the printer while the
label comes out blank. It is also the second thing to check on a ribbon error.

---

## The test pattern

**Print quality → Print test pattern**, or
`POST /print-cloud/printers/{printer_id}/test-pattern`.

One label carrying:

- a **density comb** — a mark every few millimetres, edge to edge — near the top,
- a **millimetre ruler** across the middle,
- the **same comb** again near the bottom,
- a caption recording the size, dpi, Darkness and Speed it was printed at.

Built by `backend/app/services/print_test_pattern.py` from geometry the caller
passes in, so it matches the stock actually loaded. Nothing is saved and RFID is
never encoded — the pattern runs on whatever roll is in the machine, which on an
RFID roll is real silicon.

### Reading it

| What you see | What it means |
|---|---|
| A gap in the **same place** on both combs | Dead heating elements — a printhead fault. Clean it; if the gap survives, replace the head. |
| Top comb prints, **bottom comb** is weak or missing | Not a position fault — the label advances under a fixed head, so this is a fault developing *during* the pass: ribbon failing, or the head browning out under load. |
| Density falls off toward **one edge** | Ribbon narrower than the print area, mis-threaded ribbon, or unbalanced head pressure. |
| Ruler stops before the label does | Content is being laid out past the media edge, or the media is narrower than the template says. |

The ruler is the point of the whole thing: it lets a fault be reported as "falls
off past 100 mm" instead of "on the right-hand side".

### Limits

- Refuses stock shorter than **10 mm** (`MIN_HEIGHT_MM`) — below that the
  minimum glyph is taller than the label and marks land off the bottom edge.
- On stock too wide to carry both comb rows inside TPCL's 200-text-field limit,
  the comb is **thinned evenly**, never truncated, and the budget is split
  before either row is emitted. Filling the top row first and letting the cap
  eat the tail of the bottom one produced 87 marks up top and 78 below on a
  350 mm label — which reads as a catastrophic bottom-row failure and is
  nothing of the kind.

### Three constraints in its construction

1. **Text elements only — never `line` or `box`.** See the known fault below.
2. **Marks are positioned, not sized.** Each mark is its own element at an exact
   coordinate rather than one long string of glyphs, because sizing a string to
   a label width means guessing a bitmap font's advance and guessing wrong
   overflows the media. A comb is also the better instrument: a gap in it is a
   location, not just a dimmer patch.
3. **Both comb rows carry identical x positions.** The rows only mean anything
   as a pair, so a mark dropped from one and not the other is not a smaller
   pattern — it is a false diagnosis.

---

## Fixed: `line` and `box` elements latched a B-EX6T1

**Reproduced 2026-09-05 over port 9100, root-caused the same day, fixed and
re-proved on the same printer.**

A template carrying a `line` or `box` element compiles to TPCL `{LC;…}`. The
printer *accepted* the command while parsing — status stayed `00` — and then
returned **status `06`, command error, at issue time**, when `{XS}` ran. The
same template with the `{LC}` removed printed.

```
PC only (control)          -> label printed
PC + one LC line           -> 06  command error      (before the fix)
PC + one LC box            -> 06  command error      (before the fix)
PC + LC box + 2 LC lines   -> 00  label printed      (after the fix)
```

The cause was two wrong fields in the emitter, not a printer quirk. From the
Line Format Command in the B-SX/B-EX interface specification:

```
[ESC] LC; aaaa, bbbb, cccc, dddd, e, f (, ggg) (, h) [LF] [NUL]
                                    ^  ^
```

* `e` is the line type: **0 is a line, 1 is a rectangle.** The emitter had the
  two the wrong way round, so a box asked for a slanted line and a line asked
  for a rectangle.
* `f` is the line width, **a single digit, 1–9,** in 0.1 mm. It was emitted
  zero-padded to two characters (`02`). A two-character value in a one-digit
  field is on its own a command error, which is why *every* ruled template
  failed rather than only the boxes.

The thickness is now clamped into 1–9, so a rule asked to be thicker than
0.9 mm prints at 0.9 mm instead of stopping the printer.

Why it survived so long: **probing TPCL without `{XS}` is a false pass.** The
error only exists at issue time, so every "is this command legal" probe that
stopped short of issuing a label reported `00` for a command the printer would
later refuse. Any future probe must issue, which means it costs a label.

This mattered more than a missing rule on a label: **a printer latched in
command error discards every job sent to it afterwards**, silently, until it is
reset (`ESC W R`).

---

## Fixed: text ran out of its element and over its neighbour

**Seen 2026-09-05 on Manor View Farm's `RFID Label V1`: the description printed
over the size box and the tag came out reading `5FFT`.**

TPCL has no equivalent of ZPL's `^FB` field block — nothing in the printer
clips a string to the box it was placed in. The emitter chose a font by HEIGHT
alone, so a value longer than its element simply carried on printing across
whatever was beside it.

Text is now fitted to the element's width: the height-matched font is kept when
it fits, and otherwise the tallest font that does fit is used and the shrink is
reported as a warning. A value that cannot fit at any size still prints, with a
warning saying so — refusing to print a label because one field is long is
worse than printing it small.

The width model is an ESTIMATE. The interface specification publishes a point
size per bitmap font but no character-width table, and the fonts are
proportional, so the compiler assumes an average advance of 0.6 em
(`_TPCL_ADVANCE_EM`). It is deliberately generous: over-estimating picks a
smaller font, which is only ugly, while under-estimating reproduces the fault.

Anything that BUILDS a template has to size its text with the same model, which
is what `tpcl_text_width_dots` is public for. The test pattern derived its
ruler labels from the requested height instead, and because TPCL snaps a small
request UP to its fixed font ladder, every one of those labels then reported
itself as overrunning.

---

## Symptom → fix

The drawer is entered by **symptom**, because a print fault is diagnosed by
looking at the label, not by reading a code. A live fault code is a second way
in: it opens the guide on the matching row. Table of record is
`PRINT_QUALITY_SYMPTOMS` in `print-quality-guide.ts`.

| Symptom | Most likely cause | First moves |
|---|---|---|
| Faint / washed out | Temperature too low, or wrong ribbon for the stock | Raise Darkness; lower Speed; check ribbon suits the stock; clean the head |
| Blurry / smeared | Temperature too high | Lower Darkness; raise Speed a step |
| White streaks down the label | Debris on the head, or dead elements | Remove ribbon, inspect, canned air, cleaner pen, test pattern, replace head |
| Prints in one area but not across the whole label | Ribbon too narrow / mis-threaded / wrong type; unbalanced head pressure | Test pattern first, then ribbon width, ribbon path, head pressure, template width |
| Ribbon error | Almost always a mis-thread, not a printer fault | Re-thread to the path diagram; check the take-up turns; confirm Thermal transfer |
| Paper jam / out of paper with media loaded | Media sensor not over the gap it should read | Move the sensor on its rail; run a sensor calibration; check the template Gap |
| Command error | Printer refused something in the stream | Remove line/box elements; reset the printer; check "View printer code" |
| Will not print, no error at all | Host side — a USB port asleep | Clear the print queue; unplug 5 s and back into the **same** port; restart |
| Head or cover open | Latch not closed, or something holding the head off the platen | Close head and cover; check nothing is trapped |

### Printhead life (Specialty Tag, "Extending Printhead Life")

- Keep tag stock **in its bag** until use. Dust between head, ribbon and tags
  damages the pins.
- Order ribbon with a **clean-start leader**: pull the white leader about
  **6 inches** through, stopping **before** the inked ribbon reaches the head,
  and the leader wipes it.
- Use a **printhead cleaner pen** between rolls, weekly, or as needed.

---

## Where the code lives

| File | Role |
|---|---|
| `frontend/src/pages/print-cloud/print-quality-guide.ts` | Density ranges + symptom table (the data) |
| `frontend/src/pages/print-cloud/PrintQualityDrawer.tsx` | The drawer |
| `frontend/src/pages/print-cloud/PrintCloudLabelDesignerPage.tsx` | Darkness range, fault banner, entry points |
| `frontend/src/pages/print-cloud/print-cloud-faults.ts` | Fault code → remedy (pre-existing; the guide defers to it) |
| `backend/app/services/print_test_pattern.py` | Builds the pattern |
| `backend/app/routers/print_cloud_labels.py` | `POST /printers/{id}/test-pattern` |
| `backend/tests/test_print_quality_ranges.py` | Keeps the UI range and the compiler clamp in step |
| `backend/tests/test_print_test_pattern.py` | Pattern never warns, never emits `{LC}`, never encodes RFID |
