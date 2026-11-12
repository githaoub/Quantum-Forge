# Thumbnail and icon art direction

The approved store art for Quantum Forge: five thumbnails and one icon, with the
prompt recipe behind each and the failure log from the ones that were rejected.
This is the note to open before generating the next batch, so the next batch looks
like it belongs to the same game.

Files live in `assets/generated/`, flat, named by what they are. Every one is a
real PNG. Roblox sniffs content rather than extension, so a JPEG renamed to `.png`
will fail on upload even though it previews fine locally.

---

## The six approved images at a glance

| file | style | subject | ratio and size | status |
| --- | --- | --- | --- | --- |
| `thumb-01.png` | Window Light | smith drawing a blade from the forge with tongs | 16:9, 1920x1080 | approved |
| `thumb-02.png` | Cinematic Leap | smith airborne over rubble with a hammer | 16:9, 1920x1080 | approved |
| `thumb-03.png` | Flat Poster | smith and a blown-open furnace door | 16:9, 1920x1080 | approved |
| `thumb-04.png` | Cinematic Leap | smith striking a glowing blade on an anvil | 16:9, 1920x1080 | approved, same family as 02 |
| `thumb-05.png` | Paper Storybook | smith driving a blade into an anvil, brick forge | 16:9, 1920x1080 | approved |
| `game-icon-01.png` | Cel Icon | bust with a raised sword, forge behind | 1:1, 512x512 | approved, current icon |

Rejected: `scrapped-gameicon.png`. Kept in the folder as a reference for what not
to prompt. Reasons are in the last section.

02 and 04 are the same style. The other three are deliberately different, and that
is fine: the thumbnails rotate across the store card, so a player sees the set as
one game with several moods, not five unrelated images. What holds them together
is not the rendering, it is the shared rules below.

---

## Shared rules

Every approved image obeys these, regardless of style.

| rule | why |
| --- | --- |
| One subject, one dominant light | two subjects at thumbnail scale read as noise |
| Gold key light, teal shadow | the whole game sits in this split, UI and world |
| Face is a flat decal | two eyes and a smile, no shading, no cheeks, no jaw |
| Hands are mitts | fingers are the fastest way to look generated |
| R6 body only | R15 invites invented elbows, knees and shoulder pads |
| Sword is simple and under 40 percent of frame | long thin shapes wobble |
| No baked text | the title goes on in post, generated letters always look wrong |
| Calm top third | the store card and the title sit there |
| Legible silhouette at 320px wide | that is roughly the real draw size in the charts |

---

## Style 01: Window Light

`thumb-01.png`. The quiet one. A smith, side on, drawing a blade out of the
furnace with tongs while the room sits in cool shadow and one window throws warm
light across the wall.

| property | value |
| --- | --- |
| finish | soft gouache, blended edges, airbrush transitions, low micro-detail |
| composition | subject right of centre, furnace and anvil fill the left, camera at chest height |
| key light | warm window shaft from the upper right, amber |
| fill and shadow | deep teal and slate blue, almost monochrome |
| palette | amber `#F2A33C`, cream `#F7E3C0`, teal `#1E5F6B`, slate `#16283A`, ember orange `#E2601F` |
| character | plain blockhead, apron and gloves, no bacon hair |
| mood | a working forge at the end of the day |

Prompt skeleton:

```
A blacksmith draws a glowing blade out of a furnace with iron tongs, side on, calm and focused.

Soft digital gouache, blended brush edges, airbrushed transitions, low micro-detail, matte.
Cool teal interior in shadow, one warm amber window shaft crossing the wall behind him, embers
in the air. Chest-height camera, subject right of centre, furnace and anvil at the left.
No outlines, no cel shading, no text.
```

Keep: the softness and the muted teal. It reads as the "before the grind" image.
Avoid: adding cel outlines or rim light, that turns it into style 03 or 02.

---

## Style 02: Cinematic Leap

`thumb-02.png` and `thumb-04.png`, one family. Low camera, hard diagonal, strong
rim light, debris frozen mid-air, subtle chromatic aberration on the fast edges.
This is the look that produced the results we liked most, and it is the default
for future hero thumbnails.

| property | value |
| --- | --- |
| finish | painterly cinematic, hard rim light, one key, crisp debris |
| composition | low angle, subject 40 to 55 percent of frame height, diagonal action into the top corner |
| key light | warm gold from behind and above |
| fill and shadow | cyan and indigo, high saturation |
| palette | gold `#FFC13D`, cyan `#7BE4FF`, indigo `#241B4A`, teal `#1B6E7A`, ember `#FF7A2F` |
| character | Bacon Hair R6, glossy plastic, soft specular, big hair mass |
| mood | the game at full speed |

The base DNA, verbatim, because this one works:

```
Modern Roblox promotional thumbnail, 16:9. Blocky R6 Bacon Hair Roblox avatar, spiky auburn
hair cap, pale blocky head with a flat decal smile, blue t-shirt under an open black jacket,
glossy injection-molded plastic shading with soft specular highlights. The environment is
hand-painted gouache with visible brush texture and thick rim light, not photoreal. Saturated
teal, indigo and molten-gold palette, volumetric god rays, dust motes, debris frozen mid-air,
subtle chromatic aberration and motion blur on fast elements. Cinematic low-angle hero
composition, strong diagonal action, depth of field, rim-lit silhouette. Clean empty sky or soft
vignette in the top third for a title. No text, no logos, no watermark, no extra fingers, no
realistic human faces.
```

Two approved scene lines to put in front of it:

```
A Bacon Hair blacksmith tumbles through the air over collapsing forge ruins, hammer in hand.
```
```
A Bacon Hair blacksmith hauls a glowing sword out of an anvil, sparks curling upward.
```

Keep: the DNA untouched. It carries composition, palette and finish in one block.
Avoid: adding paragraphs about fire, metal or anatomy. Every extra paragraph
flattens the painting. One scene sentence, then the DNA, nothing else.

---

## Style 03: Flat Poster

`thumb-03.png`. The graphic one. Almost no texture: solid fills, hard cel steps,
cream background, one orange fire shape. Reads like a printed poster and survives
the heaviest downscale of the set.

| property | value |
| --- | --- |
| finish | flat gouache, hard cel steps, visible brush only at the edges |
| composition | subject left, furnace door right, both full height, centred horizon |
| key light | cool cream from the left, fire from the right |
| palette | cream `#F3E4C8`, teal `#2E8B85`, navy `#1D2B45`, orange `#F04E1F`, blue shirt `#2E9BD6` |
| character | Bacon Hair R6, plaid jeans, black jacket, arms in a wide action pose |
| mood | the moment the furnace gives up |

Prompt skeleton:

```
A Bacon Hair blacksmith throws one arm up as the furnace door blows open and fire pours out.

Flat graphic gouache poster, hard cel shading in two or three steps, solid opaque fills, minimal
brush texture, bold readable shapes. Cool cream wall, teal shadow, one large orange fire shape,
embers as flat flakes. Character left, furnace right, eye-level camera, wide composition.
No gradients, no rim light, no glow, no text.
```

Keep: the flatness. It is the only style that still reads at 48px on a phone.
Avoid: glow and rim light, they break the poster into a render.

---

## Style 04: Paper Storybook

`thumb-05.png`. Warmer and softer than the rest: paper grain, thick painted
contour, muted green-teal, a cream paper margin around the art. Reads like a
painted plate in a book about the forge.

| property | value |
| --- | --- |
| finish | storybook gouache on textured paper, thick painted outlines, dry brush |
| composition | subject right of centre, anvil left, brick arch framing the top |
| key light | one shaft from the upper left, warm cream |
| palette | parchment `#F6EEDC`, sea green `#2C8C82`, slate `#26303F`, brick `#B4553C`, flame `#F25A24` |
| character | Bacon Hair R6, leather apron, jeans, sneakers, both hands on a sword |
| margin | the cream paper border is part of the style, crop it only for upload |
| mood | a craft that has been going on for generations |

Prompt skeleton:

```
A Bacon Hair blacksmith drives a glowing blade into an anvil with both hands, leather apron,
brick forge glowing behind him.

Storybook gouache on textured paper, visible paper grain, thick painted contour lines, dry brush
edges, muted sea green and parchment palette, one warm shaft of light from the upper left, brick
arch overhead, sparks as flat painted flecks. Warm, calm, illustrative.
No photorealism, no glow bloom, no text.
```

Keep: the paper grain and the muted palette. It is the one "cosy" image.
Avoid: adding bloom or chromatic aberration, that pulls it back into style 02.

---

## Style 05: Cel Icon

`game-icon-01.png`. The current game icon. A bust of the Bacon Hair smith with a
crystal sword raised, forge doorway on the right, vaulted skylight above. Hard
outlines, glossy cel shading, large readable face, one bright blade.

| property | value |
| --- | --- |
| format | 1024 x 1024, square, PNG |
| finish | clean cel shading, hard outline, glossy plastic, three value steps |
| composition | head and shoulders, centred, head about 45 percent of frame height, sword filling the left edge |
| key light | skylight above, forge fire right |
| palette | gold `#FFC13D`, cyan `#7BE4FF`, indigo `#241B4A`, stone `#4A5A6E`, fire `#F2541B` |
| test | must still read at 48px: hair shape, sword, face, fire |
| mood | the shop sign |

Prompt skeleton:

```
A Bacon Hair blacksmith holds a glowing crystal sword upright beside his head, forge doorway
behind him, seen from the chest up.

Clean cel-shaded game icon, hard dark outline, glossy plastic highlights in three steps, large
readable face, warm forge fire on the right, cool skylight from above. Centred bust, head about
45 percent of the frame height, sword along the left edge. Bold silhouette, high contrast,
readable at 48 pixels. No text, no logos.
```

Keep: the outline and the big face. That is what survives at icon size.
Avoid: full body, crossed props, busy corners.

---

## The rejected icon

`scrapped-gameicon.png`. Do not prompt this again.

| what it does | why it fails |
| --- | --- |
| full body, sword swung across the frame | at 48px the sword and the body fuse into one diagonal smear |
| sword crosses the face | the eye goes to the intersection, not the character |
| detailed hair strands, eyebrows, cheeks | the face stops reading as a decal and starts reading as generated |
| gold rim outline around the silhouette | sticker effect, looks pasted on |
| fire in both bottom corners | noise at small size, and it fights the forge already in frame |
| three light sources | nothing reads as the key light |

The lesson: an icon is a sign, not a scene. Bust, one prop, one light, big shapes.

---

## Reusable blocks

Paste these as-is when writing a new prompt.

**R6 body lock.** Prevents invented joints.

```
Blocky R6 Roblox avatar: one solid beveled torso block, single-piece arms and legs with no
elbows or knees, white blocky mitt hands with no fingers, oversized block head sitting directly
on the torso with no neck. Face is a flat decal: two black oval eyes and one simple smile, no
nose, no shading on the face.
```

**Bacon Hair lock.** The character's identity.

```
Bacon Hair: spiky auburn hair cap as four or five large angular chunks with no individual
strands, blue t-shirt under an open black jacket, dark jeans.
```

**Metal lock.** Kills the melting-sword look.

```
One straight blade with parallel edges and a clean point, short crossguard, wrapped grip, solid
paint, a single hard highlight along the edge, no ornament, no runes, no melting edges.
```

**Fire lock.** Painted fire instead of bloom.

```
Fire painted in a few large solid shapes of orange, red and cream, each flame one flat colour,
hard edges, no gradation, no airbrush, no glow spill.
```

**Negative tail.** Same ending on every prompt.

```
No text, no logos, no watermark, no extra fingers, no realistic human faces, no lens flare.
```

---

## Production checklist

Run this before uploading.

1. **Format.** 1920x1080 for every thumbnail, 512x512 for the icon. PNG, not JPEG, and under 3 MB. Roblox downsamples anything larger and the store card starts to look soft, which is what happened with the first 1024 icon and the 1376-wide thumbnails.
2. **Top edge.** No pale band, no white bar, no hard horizontal seam. The model sometimes lays a title plate over the top; crop it off rather than painting over it.
3. **Paper margin.** Style 04 ships with one on purpose. Any other style with a cream border is an accident, crop it.
4. **Crop math.** Cutting a band off the top changes the ratio. Re-crop the sides to hold 16:9, anchored on the character, then upscale to 1920x1080.
5. **Downscale test.** Look at the image at 320px wide. If the face, the blade or the fire disappears, the composition is wrong, not the render.
6. **Icon test.** Look at the icon at 48px. If you cannot tell it is a forge, simplify.
7. **Title.** Set `QUANTUM FORGE` in post, gold `#FFC13D`, hard drop shadow, inside the calm third. Never let the model draw it.
8. **Keep the source.** Approved art stays in `assets/generated/` with the same name, so the store listings and this note never drift apart.

---

## Failure log

Everything here cost a generation to learn.

| symptom | cause | fix |
| --- | --- | --- |
| elbows, knees and shoulder pads appear | the prompt said R15 | say R6, single-piece limbs, no joints |
| face looks like a melted painting | the face was lit and shaded like skin | flat decal face, no shading, no cheeks |
| sword bends and melts | glow words plus a long foreshortened blade | side-on blade, solid fill, glow contained inside the blade |
| fire becomes orange fog | `molten`, `bloom`, `god rays` in the same paragraph | painted fire lock, three flat values |
| the whole image goes flat and cheap | scene paragraphs added for fire, metal, anatomy | one scene sentence plus the DNA, nothing else |
| character looks pasted on | painted background with a soft-lit character | hard rim light and a shared key light, or cel shading |
| white bar across the top | the model inserted a title plate | crop the band, then re-crop sides to 16:9 |
| cream frame around the art | the model rendered a paper plate | crop to the art, or keep it only in style 04 |
| jpg previews fine but Roblox rejects it | extension renamed, bytes unchanged | re-encode to real PNG |
| the art looks soft on the store card | uploaded below the display size | ship 1920x1080 thumbs and a 512 icon, Lanczos up plus a light unsharp |
| upload rejected for size | full-res PNG over the cap | re-save with optimize, target under 3 MB |
