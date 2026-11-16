# Demo test media

Images to load into SPAI's **Test Media** panel when there's no live
camera, or to show a specific moment on cue. AirDrop them to the Vision Pro
(they land in Photos) before the demo.

| File | What SPAI shows | Use it for |
| --- | --- | --- |
| `gloves-on.jpg` | Gloves on, contamination risk low | Passing the glove check at Decontamination or Inspection |
| `bare-hand.jpg` | **Bare hand visible**, workflow halts | The contamination alert and Pip jumping to it |
| `tray-three-instruments.jpg` | Halsted Mosquito Forceps, Operating Scissors, Babcock Tissue Forceps; tray loaded | Instrument naming; the count sheet at Tray Assembly |
| `tray-two-instruments-a.jpg` | Halsted Mosquito Forceps, Babcock Tissue Forceps | Naming; a count-sheet mismatch (one missing) |
| `tray-two-instruments-b.jpg` | Babcock Tissue Forceps, Adson Dressing Forceps | Naming |
| `tray-empty.jpg` | Tray empty | Showing an empty tray doesn't pass |

Results above were checked against the current server models. Each image
was run through `/analyze`.

Known quirk: `tray-empty.jpg` also shows a faint "glove" on the tray's
edge. It doesn't affect anything in the demo.

## Credits

The four `tray-*.jpg` images are from the ASTRA Surgical Instruments
dataset (https://universe.roboflow.com/astra-juyrg/astra-surgical-instruments-erspj),
licensed CC BY 4.0. `gloves-on.jpg` and `bare-hand.jpg` are from SPAI's own
test footage.
