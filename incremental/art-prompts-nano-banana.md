# Prompting Nano Banana 2 for Quantum Forge badges

Working notes from the 2026-11-10 run: 15 badge prompts written for the Fleet, Rune
and Tech lists, 14 images returned. This is the reference for writing the next batch
so the result looks painted by a person rather than rendered by a model.

---

## The output contract

Every badge in this game follows the same physical format, and the prompt has to
carry it because the model has no other context:

| property | value |
| --- | --- |
| canvas | 1024 x 1024, square |
| shape | one perfect circle, disc radius about 47% of the canvas |
| corners | light grey checkerboard, transparent in intent |
| margin | a clean empty band between the disc and the frame edge |
| text | none, ever, including runic letters and numbers |
| final draw size | 29 to 40 real pixels in a list row |
| file | JPG, saved with the item's slug as the name |

The draw size is the number that matters and the one that gets forgotten. A
feature that is beautiful at 1024 and gone at 40 is a failed badge, so every prompt
carries an explicit legibility section.

---

## The block structure

Each item is one continuous block. The order is not decorative: the model reads
top to bottom and the early sections set the register the rest is judged against.

| section | job |
| --- | --- |
| heading | `n. key - "Display Name"` |
| Intent | what the item does in the game, and what the picture is about |
| difference note | how it differs from the nearest other badge |
| opening paragraph | medium, market, and the anti-vector clause |
| SUBJECT | the one prop, its forms, and what is excluded |
| PALETTE | five or six hexes, a named harmony, and the shadow rule |
| LINE | contour behaviour |
| LIGHT AND SHADOW | one key, one bounce, flat painted shading |
| SURFACE | paper, granulation, specks, human imperfections |
| LEGIBILITY | px size, feature count, minimum feature size |
| COMPOSITION | canvas, radius, margin, asymmetry |
| NEGATIVE | long comma list, family additions, AI tells |
| Settings / Save as | tool flags and output path |

### Intent

Two or three sentences of plain game design. Why the item exists, what the player
is buying, what the picture is trying to say. The model uses this to pick a pose,
so a vague intent produces a generic object standing still.

> Intent: a five-minute run through the near belt. Cheap, safe, and back before the
> kettle boils. The picture is the haul, not the travel: the drone has already
> grabbed something ridiculous and is dragging it home.

### The difference note

One paragraph naming the closest other badge and stating what this one is not.
This is the highest-yield paragraph in the block. Two items in the same family will
converge unless the difference is written down.

> The difference from Deep Salvage matters: that badge is a vertical cable with a
> hull hanging under it. This one is horizontal, low and light, a small tug hauling
> a compact ball of junk sideways.

The store badges already needed this: Auto-Vent is a standing valve with one upward
plume, Instant Vent is an elbow pipe firing sideways. Without that sentence the
model draws the same valve twice.

### The opening paragraph

One paragraph that locks the medium and the market before anything else is
described. It is the same in every block, and it is what stops the output drifting
into app-icon rendering.

> Hand-painted game badge illustration, perfectly circular, centred on a square
> canvas with fully transparent corners. Painted by a professional illustrator in
> gouache, ink and coloured pencil, the kind of original art printed on a tabletop
> game box or a mid-century children's book plate. Rich, saturated, hand-mixed
> colour, layered wet into wet and then drawn over while damp. Not a vector icon,
> not clipart, not a 3D render, not an app icon.

Three things are doing work here: a named medium (gouache, ink, coloured pencil), a
named market (tabletop game box, children's book plate), and an explicit refusal
list at the end. "Not a vector icon" is not politeness, it is a routing instruction.

### SUBJECT

One prop. Not a scene, not a crowd, not a diorama. Describe three to five forms in
the order the eye should find them, their spatial relationship, and then list what
is excluded. The exclusions are load-bearing: without them the model adds stars,
ground, pipes and a second machine.

> SUBJECT: a chunky salvage tug drone seen from the side, leaning back against a
> load. Its body is a squat riveted box of burnt orange and brass, with one big
> round lens eye at the front and a stubby thruster at the back, small braced legs
> underneath. A horseshoe magnet hangs from a short arm under its nose, and stuck
> to the magnet is a compact ball of junk about half the drone's size: a bent
> bathtub, a traffic cone, a satellite dish, half a bicycle wheel, all in different
> colours so the clump reads as a collection rather than a mass. [...]
> Nothing else in the frame: no stars, no planet, no second drone, no ground, no
> scenery.

Note the colour words inside the subject. They are repeated formally in PALETTE,
but repeating them here keeps the model from defaulting to grey while it is still
deciding what the object is.

### PALETTE

The section that fixes "looks AI generated". Five or six hexes, a named harmony,
and the shadow rule. Bodies are coloured metal, never black with a rim light: a
near-black subject with a steel rim is exactly how a 3D render looks, and it was
the single biggest failure of the earlier drafts.

> PALETTE: a complementary pairing, cool field against a warm machine. Field
> turquoise (#2ED3C6) with deep teal (#0B6B6B) at the rim and two paler sweeps
> where the paper shows through. The drone is burnt orange (#E2703A) over brass
> (#F0A64B), its junk ball a mix of rust (#B4552A), mustard (#E8B23C), sage
> (#8FA98A) and cream (#FFF3D6). Shadows are umber (#6B3A1E), never grey. The ink
> contour is near-black (#141018) and it is the only true black in the image.

Rules:

- Name the harmony: complementary, split-complementary, analogous, triadic.
- Every material gets a base, a shadow and a highlight, all three as hexes.
- Shadows are coloured: umber on warm materials, indigo on cool ones.
- The ink contour is the only true black in the image.
- The field is painted, with two paler sweeps where the paper reads through.

### LINE

One paragraph, identical in every block. It is short and it is doing three jobs:
variable weight, visible hand wobble, and a guarantee that the disc edge is inked
like everything else.

> LINE: confident hand-inked contours, a loaded brush line whose weight swells and
> tapers, with the small live wobble of a real hand. The outer disc edge gets the
> same treatment. Contours are the strongest value on the page and never break.

### LIGHT AND SHADOW

Separate from colour, because a palette alone does not describe illumination.
Warm key, cool bounce, flat shapes with crisp edges, two tones per material, no
airbrush. Close with the rule that makes painted shading read as paint.

> LIGHT AND SHADOW: one warm key from the upper left, one cool bounce from below.
> Shading is painted as flat shapes with crisp edges, two tones per material, never
> airbrushed. Warm light means cool shadows: the orange body goes to umber-plum in
> shadow, not to black.

### SURFACE

Paper and hand. This is where the human tells live, and they are stated as
requirements rather than suggestions.

> SURFACE: fine tooth of cold-press watercolour paper, gentle granulation in the
> turquoise rim, a scatter of pigment specks, one dry-brush scratch along the junk
> ball. The paint sits slightly over the contour in one or two places, the way a
> hand works. Perfectly clean edges are a machine tell. The texture is a whisper,
> never a layer of noise.

### LEGIBILITY

State the final pixel size, the feature count, the 4% minimum, and the one shape
that must survive shrinking. This section prevents the model from adding detail
that dies at 40px.

> LEGIBILITY: this prints at 40 pixels in an expedition row. One drone, one magnet,
> one junk ball. Minimum feature size 4% of the canvas. The junk must read as a
> clump with hard silhouettes, not as dust, when the badge is 29 real pixels wide.

### COMPOSITION

Canvas, radius, margin, and one deliberate imperfection.

> COMPOSITION: 1:1 square, 1024x1024, badge centred, disc radius about 47% of the
> canvas leaving a clean empty margin at the edge. Slight asymmetry: the load sits
> a touch low, as if the drawing was placed by hand.

The asymmetry line matters more than it looks. Perfect centring reads as
generated, because a person placing art by eye leaves it slightly off.

### NEGATIVE

Long, comma separated, and grouped by intent. Start with the universal bans, then
the family additions, then the AI tells.

Universal: `text, letters, numbers, labels, logo, watermark, signature, UI
elements, frame or border around the square, vector, flat sticker, clipart,
corporate illustration, gradient mesh, airbrush, glossy plastic, chrome,
photograph, 3D render, lens flare, bloom, noise, grain, halftone, thin scratchy
pencil lines, crosshatching, engraving, muddy or desaturated colour, sepia, dark
or black background, filled corners, multiple objects, clutter, isometric,
perspective distortion`

AI tells, added for this pipeline: `AI-generated look, machine-smooth gradients,
uniform line weight, plastic 3D render, generic mobile game icon, glossy app icon,
neon glow, black drop shadows, perfect symmetry, digital airbrush, photo texture
overlay`

Family additions:

| family | additions |
| --- | --- |
| Fleet | star field, planet, nebula, second drone, fleet, cockpit, pilot, rocket flame, exhaust cloud |
| Runes | carved letters, runic alphabet, glyphs, sigils, scenery, mist, more than one rune object |
| Tech | blueprint grid, floating gears, workshop scene, smoke clouds, spark storm, more than one machine |

### Settings and save path

> Settings:  --ar 1:1 --style raw --stylize 150
> Save as:   assets/generated/gamepasses/\<slug\>.jpg

The flags are inherited from the earlier Midjourney pass. Nano Banana ignores them;
the text is the prompt. Keeping the line means the block still works if it is ever
run somewhere that reads flags.

---

## The five rules that do the work

1. **One prop, never a scene.** The field is the world. A horizon, a ground plane
   or a second object is what turns an icon into an illustration.
2. **Colour is a section, not an adjective.** Every material gets base, shadow and
   highlight as hexes, and every badge gets a named harmony. Objects are copper,
   brass, teal, plum, sienna, coral, mint and saffron, not black.
3. **Shadows are coloured; the ink contour is the only black.** This is the rule
   that killed the plastic look.
4. **Write the human tells.** Paint over the line, dry-brush, pigment specks,
   slight asymmetry. The model will not add imperfection unless asked, and
   perfection is the tell.
5. **Differentiate from the nearest neighbour in its own paragraph.** Two items in
   one family converge without it.

---

## What produced bad output, with the fix

| output problem | cause | fix |
| --- | --- | --- |
| cinematic digital painting | prompt said "heavy metal album cover", "epic", "louder" | name the medium and the market instead: gouache, tabletop game box |
| plastic 3D object | subject described as near-black with a steel rim light | give the body a real colour and a coloured shadow; black only in the contour |
| flat grey render | no palette section, colours left to the model | 5 to 6 hexes, base + shadow + highlight per material, named harmony |
| two entries look the same | no difference paragraph | state what the nearest badge is and what this one is not |
| extra props appear | subject had no exclusion sentence | end SUBJECT with "nothing else in the frame: ..." |
| text or runes appear | negative list did not forbid them | add `text, letters, numbers, carved letters, runic alphabet` |
| mush at 40px | too many equal shapes | one hero, one accent, 4% minimum feature, state what must survive |
| white square corners instead of checkerboard | "fully transparent corners" rendered as flat white | say "light grey checkerboard corners" as well as transparent |
| beautiful but dead | no posture and no byproduct | every prop leans, braces or recoils, and one thing curls out of it |

---

## Sizes and fields by family

| family | list | drawn at | field | rim |
| --- | --- | --- | --- | --- |
| Fleet | expedition rows, 3 | 40px | turquoise / sea blue / periwinkle | deep teal, marine, indigo |
| Runes | rune shelf, 4 | 52px | orchid / lavender / violet / magenta violet | plum, deep violet, indigo |
| Tech | tech cards, 8 | 56px | saffron / honey / amber / pale gold | burnt amber, ochre |

Fields are per item rather than per family, but they stay inside a family hue band
so a list still reads as a list.

---

## Copy template

```
================================================================================
 n. key  -  "Display Name"
================================================================================

Intent: <why the item exists, and what the picture is about>

The difference from <nearest badge> matters: <what this one is not>

--------------------------------------------------------------------------------
 PROMPT - paste into the prompt field
--------------------------------------------------------------------------------

Hand-painted game badge illustration, perfectly circular, centred on a square
canvas with fully transparent corners. Painted by a professional illustrator in
gouache, ink and coloured pencil, the kind of original art printed on a tabletop
game box or a mid-century children's book plate. Rich, saturated, hand-mixed
colour, layered wet into wet and then drawn over while damp. Not a vector icon,
not clipart, not a 3D render, not an app icon.

SUBJECT: <one prop, three to five forms, spatial arrangement, colour words
inline>. Nothing else in the frame: no <x>, no <y>, no ground, no scenery.

PALETTE: <named harmony>. Field <hex> with <hex> at the rim and two paler sweeps
where the paper shows through. The object is <hex> over <hex>, with <hex>
accents. Shadows are <hex>, never grey. The ink contour is near-black (#141018)
and it is the only true black in the image.

LINE: confident hand-inked contours, a loaded brush line whose weight swells and
tapers, with the small live wobble of a real hand. The outer disc edge gets the
same treatment. Contours are the strongest value on the page and never break.

LIGHT AND SHADOW: one warm key from the upper left, one cool bounce from below.
Shading is painted as flat shapes with crisp edges, two tones per material, never
airbrushed. Warm light means cool shadows.

SURFACE: fine tooth of cold-press watercolour paper, gentle granulation in the
rim, a scatter of pigment specks, one dry-brush scratch along <feature>. The paint
sits slightly over the contour in one or two places, the way a hand works.
Perfectly clean edges are a machine tell. The texture is a whisper, never a layer
of noise.

LEGIBILITY: this prints at <px> pixels in a <list>. One <a>, one <b>, one <c>.
Minimum feature size 4% of the canvas. <the one shape that must survive>.

COMPOSITION: 1:1 square, 1024x1024, badge centred, disc radius about 47% of the
canvas leaving a clean empty margin at the edge. Slight asymmetry: <what is off
centre>, as if the drawing was placed by hand.

--------------------------------------------------------------------------------
 NEGATIVE - paste into the negative field (drop the word NEGATIVE:)
--------------------------------------------------------------------------------

NEGATIVE: <universal list> + <family additions> + <AI tells>

--------------------------------------------------------------------------------
 Settings:  --ar 1:1 --style raw --stylize 150
 Save as:   assets/generated/gamepasses/<slug>.jpg
--------------------------------------------------------------------------------
```

---

## Generated set, 2026-11-10

All fifteen returned. The filenames Gemini assigns are opaque, so the mapping is
recorded here. The JPGs now live in `assets/badges/source/`; the normalised discs
are one level up in `assets/badges/`.

| prompt | item | generated file |
| --- | --- | --- |
| 1 | Debris Sweep | `Gemini_Generated_Image_dkxvhtdkxvhtdkxv.jpg` |
| 2 | Deep Salvage | `Gemini_Generated_Image_m621ym621ym621ym.jpg` |
| 3 | Void Run | `Gemini_Generated_Image_nw44qunw44qunw44.jpg` |
| 4 | Ember Rune | `Gemini_Generated_Image_u1tx1vu1tx1vu1tx.jpg` |
| 5 | Tempo Rune | `Gemini_Generated_Image_emonj4emonj4emon.jpg` |
| 6 | Edge Rune | `Gemini_Generated_Image_ngs7nlngs7nlngs7.jpg` |
| 7 | Prism Rune | `Gemini_Generated_Image_u9a6bfu9a6bfu9a6.jpg` |
| 8 | Forged Momentum | `Gemini_Generated_Image_7nqga7nqga7nqga7.jpg` |
| 9 | Thermal Calibration | `Gemini_Generated_Image_ohbao2ohbao2ohba.jpg` |
| 10 | Drone Lattice | `Gemini_Generated_Image_wkm8e4wkm8e4wkm8.jpg` |
| 11 | Vent Efficiency | `Gemini_Generated_Image_xrskwxxrskwxxrsk.jpg` |
| 12 | Offline Core | `Gemini_Generated_Image_oa16fsoa16fsoa16.jpg` |
| 13 | Critical Forge | `Gemini_Generated_Image_q2b64bq2b64bq2b6.jpg` |
| 14 | Phantom Hammer | `Gemini_Generated_Image_tden19tden19tden.jpg` |
| 15 | Head Start | `Gemini_Generated_Image_pc0k5ypc0k5ypc0k.jpg` |

All are 1024x1024 JPG. Every one except Debris Sweep has the light grey
checkerboard corners the prompt asked for; Debris Sweep came back on a flat white
field, which the normaliser keys the same way but which is worth controlling in the
prompt next time.

---

## Checklist before running a new block

- [ ] Intent names what the item does and what the picture is about
- [ ] Difference paragraph names the nearest existing badge
- [ ] SUBJECT has one prop, three to five forms, and an exclusion sentence
- [ ] PALETTE has five or six hexes and a named harmony
- [ ] Every material has base, shadow and highlight
- [ ] Shadows are coloured; black appears only as the ink contour
- [ ] LIGHT AND SHADOW names one key and one bounce
- [ ] SURFACE contains the human tells
- [ ] LEGIBILITY names the px size and the shape that must survive
- [ ] COMPOSITION has 47% radius, margin and a slight asymmetry
- [ ] NEGATIVE carries universal + family + AI tells
- [ ] Save name matches the slug the normaliser expects

---

## See also

Badges are 40px props. Thumbnails and the game icon are 320px scenes, with their
own five styles, prompt recipes and failure log: [[art-thumbnails]].

