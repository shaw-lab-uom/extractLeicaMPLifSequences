# extractLeicaMPLifSequences

Pull every scan out of a Leica `.lif` file into plain, calibrated image files — without opening the `.lif` in LAS X or ImageJ.

Written for multiphoton recordings (Z-stacks, time series, tile-scan navigator mosaics, single snapshots), but works on any `.lif`.

## What it does

Point it at a folder of `.lif` files. For each `.lif`, every distinct scan inside it is identified and written out alongside the `.lif`:

| Scan type | Output |
|---|---|
| Z-stack | multi-page calibrated TIFF (one page per slice) |
| Time series / movie | multi-page calibrated TIFF (one page per frame) |
| Single snapshot / already-merged tile scan | single calibrated TIFF |
| **Unmerged tile-scan mosaic** (e.g. a Navigator spiral saved without ticking "merge") | stitched into one image from the per-tile stage-position metadata, then written as a contrast-stretched 8-bit **PNG** |
| Multi-channel data | split into one file per channel, suffixed `_C1`, `_C2`, … |

Pixel size, Z-step and frame interval are embedded using ImageJ's TIFF convention, so the outputs re-open calibrated.

Output names: `<lifFileName>_<scanName>_<YYYYMMDD>[_C#].tif` (or `.png` for a mosaic).

### Mosaic stitching

Unmerged mosaics are reconstructed from each tile's recorded stage position. Two known Leica/Bio-Formats quirks are corrected **empirically** (measured from the real tile overlaps, not assumed):

- a tile's pixel array can be mirrored/rotated relative to its true position;
- the X and Y stage-position fields can be swapped.

The correction is chosen from whichever `{channel, swap}` combination gives the single highest-confidence answer, then tiles are exposure-matched, flat-field corrected, and feather-blended. A zoom-in / repeat sub-scan of a region already inside the main grid (LAS X can give these the same scan name) is detected and excluded so it doesn't corrupt the mosaic.

Mosaics are written as PNGs rather than TIFFs on purpose: they are dim by nature and a plain 16-bit TIFF opens looking black in most viewers until manually contrast-adjusted; they are for visual reference, not quantitative measurement.

## Requirements

- MATLAB with the Image Processing Toolbox (and the Statistics Toolbox, for `prctile`).
- **Bio-Formats MATLAB toolbox (`bfmatlab`)** — download `bfmatlab.zip` from <https://www.openmicroscopy.org/bio-formats/downloads/> (under the latest version's *artifacts*), unzip it, and add the folder to your MATLAB path (or drop it in `Documents\MATLAB`, which is on the path automatically). The script stops with a clear message if it can't find `bfGetReader`.

## Usage

1. Open `extractLeicaMPLifSequences.m` and set `EXP_DIR` to the folder containing your `.lif` file(s).
2. Run the script (F5). Every `.lif` directly inside `EXP_DIR` is processed in turn; outputs are written into `EXP_DIR`.

For finer control, call the worker directly:

```matlab
lifToTiffs('Z:\path\to\folder', 'my_recording.lif');
% Name-value options: 'OutDir', 'TileAnchor' (center|corner), 'FeatherPx',
% 'FlatField' (true/false), 'TileOrientation' ('auto' | none|fliplr|flipud|rot180),
% 'Verbose'. Returns a summary table (name, type, nTiles, orientation, files).
```

Opening multi-GB files over a network share is retried a few times before giving up.

## Files

```
extractLeicaMPLifSequences.m   entry point — loops over .lif files in EXP_DIR
functions/
  lifToTiffs.m                 per-file exporter; orchestrates everything below
  identifyLifGroups.m          groups Bio-Formats series into real scans; flags mosaics; drops repeat sub-scans
  getTileGeometry.m            reads per-tile size / pixel size / stage position
  chooseTileCorrection.m       picks the orientation + X/Y-swap correction for a mosaic
  detectTileOrientation.m      empirically tests whether tiles need flipping to match their stage position
  clusterTilesBySpatialCoherence.m  splits tile positions into connected groups
  stitchTileGroup.m            reconstructs and blends one unmerged mosaic
  readResampledPlanes.m        reads one channel's plane from each tile (downsampled, for the geometry tests)
  matchTileIntensity.m         per-tile exposure matching
  estimateFlatField.m          self-estimated illumination/gain field
  applyFlatField.m             applies the flat field to a set of tiles
  writeSpiralPNG.m             writes a mosaic as a contrast-stretched 8-bit PNG
  exportLifSeries.m            writes one non-mosaic series (stack / movie / snapshot) to calibrated TIFF
  writeImageJTiff.m            single-page TIFF with ImageJ calibration tags
  imagejTagStruct.m            builds the ImageJ-hyperstack tag struct
  readPlaneWithRetry.m         bfGetPlaneAtZCT wrapper with retries (network I/O)
  sanitizeFileName.m           makes scan names safe for Windows filenames
```

## Notes

- Everything is written next to the `.lif` by default; the `.lif` itself is never modified.
- Reading is done entirely through Bio-Formats, so any `.lif` it can open will load; the mosaic-stitching path is the part tuned to Leica multiphoton tile scans.
