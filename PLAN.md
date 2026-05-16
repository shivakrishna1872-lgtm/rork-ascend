# Make physique & PSL AI more forgiving about photo quality

**Goal:** Stop the analysis from being picky about how photos are framed, lit, or angled. People should be able to snap quick photos and still get a real score.

**What changes for the user**

- **Physique scan**
  - Capture button stays Ready unless almost nothing is detected — partial bodies, waist‑up shots, slightly off‑center framing, and dim/bright rooms all pass.
  - On‑screen warnings only appear for the truly broken cases (no body at all, pitch black, blown out). Cropped legs, side angles, and off‑center poses no longer show a warning.
  - The AI itself is told to score based on what's visible and not to dock points for partial framing, distance, lighting, or camera angle. It treats imperfect photos as normal input, not as errors.

- **PSL (face) scan**
  - The AI is instructed to handle slight head turns, varied lighting, glasses/hats, and casual selfies without lowering the score for "bad photo quality."
  - Symmetry, jawline, thirds, etc. are scored from what is measurable; anything not clearly visible is estimated from the rest, not penalized.
  - Confidence dips slightly on rough photos instead of refusing/under‑scoring.

- **Both flows**
  - Clearer, friendlier guidance text ("Any decent photo works — we'll average across all of them") replaces the strict positioning copy.
  - Error messages reworded so users feel encouraged to keep going rather than re‑shoot.

**What stays the same**

- Multi‑photo averaging, stability, history anchoring, and the existing scoring ranges are unchanged — scores still won't fluctuate wildly.
- Camera permission handling and capture UI stay as they are.