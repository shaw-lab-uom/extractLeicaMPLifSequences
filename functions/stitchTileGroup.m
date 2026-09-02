function nTilesUsed = stitchTileGroup(r, omeMeta, seriesIdx, outFileBase, opts)
% =========================================
% Script: stitchTileGroup.m
% Created: 2026-08-26
% Purpose: Reconstructs one unmerged tile-scan mosaic (e.g. an unmerged
%          LAS X Navigator spiral) into a single stitched image:
%            1. places every tile using its stage-position metadata,
%            2. corrects tile pixel data against a known/pre-detected
%               mirror-rotation between the tile and its stage position
%               (see detectTileOrientation.m, run once per scan by the
%               caller - not per mosaic, since it's a reader/hardware
%               property, not something that varies tile-set to tile-set),
%            3. corrects per-tile exposure/gain drift from live-scan
%               auto-exposure (matchTileIntensity) and any remaining
%               shared spatial vignette (a self-estimated flat field),
%            4. blends overlaps with a linear feather,
%            5. writes an 8-bit, contrast-stretched PNG (writeSpiralPNG)
%               rather than a calibrated TIFF - these mosaics are dim by
%               nature and used for visual reference (finding vessels,
%               checking window quality), not quantitative measurement,
%               so a viewer-ready PNG is more useful than a 16-bit TIFF
%               that opens looking black until manually contrast-adjusted.
%
% Inputs:
%   r            - open Bio-Formats reader
%   omeMeta      - r.getMetadataStore()
%   seriesIdx    - 0-based series indices making up this mosaic (row/col vec)
%   outFileBase  - full output path WITHOUT extension/channel suffix
%   opts         - struct: TileAnchor ('center'|'corner'), FeatherPx,
%                  FlatField (logical), TileOrientation (concrete value:
%                  'none'/'fliplr'/'flipud'/'rot180' - resolved by the
%                  caller, see lifToTiffs.m), SwapXY (logical, concrete -
%                  resolved by the caller; corrects a documented
%                  Bio-Formats LIF stage X/Y mislabelling quirk,
%                  independent of TileOrientation), Verbose (logical)
% Outputs:
%   nTilesUsed   - number of tiles stitched (for the caller's summary)
% Last modified: 2026-08-26 - orientation/swapXY are detected per mosaic
%                group independently (a shared-per-scan-name detection
%                was found to pick the wrong answer when a scan's
%                channel-count groups come from genuinely different tile
%                sets); added SwapXY correction
% =========================================

seriesIdx = seriesIdx(:)';
nTiles = numel(seriesIdx);
nTilesUsed = nTiles;

geom = getTileGeometry(r, omeMeta, seriesIdx, opts.TileAnchor, opts.SwapXY);

if any(geom.szZ > 1) || any(geom.szT > 1)
    error('stitchTileGroup:unsupportedDims', ...
        'Tiles for "%s" contain Z or T stacks (not just single 2D snapshots) - mosaic stitching of tile stacks is not supported by this function; inspect this scan manually.', outFileBase);
end
if numel(unique(geom.nCh)) > 1
    error('stitchTileGroup:mixedChannels', ...
        'Tiles for "%s" have inconsistent channel counts (%s).', outFileBase, mat2str(unique(geom.nCh)'));
end
nChannels = geom.nCh(1);
outPxSize = geom.outPxSize;

minX = min(geom.left_um); maxX = max(geom.right_um);
minY = min(geom.top_um);  maxY = max(geom.bottom_um);
canvasW = ceil((maxX-minX)/outPxSize);
canvasH = ceil((maxY-minY)/outPxSize);

if opts.Verbose
    fprintf('[stitchTileGroup] "%s": %d tiles -> canvas %dx%d px at %.4f um/px, %d channel(s), orientation "%s", swapXY=%d\n', ...
        outFileBase, nTiles, canvasW, canvasH, outPxSize, nChannels, opts.TileOrientation, opts.SwapXY);
end

for ch = 1:nChannels
    planes = readResampledPlanes(r, seriesIdx, ch, geom.pxX, outPxSize);
    planes = cellfun(@(p) applyOrientation(p, opts.TileOrientation), planes, 'UniformOutput', false);

    if opts.FlatField
        planes = matchTileIntensity(planes, opts.Verbose);
        planes = applyFlatField(planes, opts.Verbose);
    end

    accum = zeros(canvasH, canvasW, 'single');
    wsum  = zeros(canvasH, canvasW, 'single');
    for i = 1:nTiles
        plane = planes{i};
        [th, tw] = size(plane);
        x0 = round((geom.left_um(i)-minX)/outPxSize)+1;
        y0 = round((geom.top_um(i)-minY)/outPxSize)+1;
        x1 = x0+tw-1; y1 = y0+th-1;
        xa = max(x0,1); ya = max(y0,1);
        xb = min(x1,canvasW); yb = min(y1,canvasH);
        if xb<xa || yb<ya, continue; end
        srcXa = xa-x0+1; srcYa = ya-y0+1;
        srcXb = srcXa+(xb-xa); srcYb = srcYa+(yb-ya);
        tilePatch = plane(srcYa:srcYb, srcXa:srcXb);
        wY = localFeatherWeights(th, opts.FeatherPx); wY = wY(srcYa:srcYb);
        wX = localFeatherWeights(tw, opts.FeatherPx); wX = wX(srcXa:srcXb);
        wPatch = single(wY(:)*wX(:)');
        accum(ya:yb,xa:xb) = accum(ya:yb,xa:xb) + tilePatch.*wPatch;
        wsum(ya:yb,xa:xb) = wsum(ya:yb,xa:xb) + wPatch;
        if opts.Verbose && mod(i,20)==0
            fprintf('[stitchTileGroup]   channel %d/%d: tile %d/%d placed\n', ch, nChannels, i, nTiles);
        end
    end

    result = accum ./ max(wsum, eps('single'));
    result(wsum==0) = 0;
    result = uint16(result);

    if nChannels > 1
        chFile = sprintf('%s_C%d.png', outFileBase, ch);
    else
        chFile = sprintf('%s.png', outFileBase);
    end
    writeSpiralPNG(result, chFile, outPxSize);
    if opts.Verbose
        fprintf('[stitchTileGroup] Wrote %s\n', chFile);
    end
end

end


function p = applyOrientation(p, variant)
switch variant
    case 'none'
    case 'fliplr', p = fliplr(p);
    case 'flipud', p = flipud(p);
    case 'rot180', p = rot90(p,2);
    otherwise
        error('stitchTileGroup:badOrientation', 'Unknown TileOrientation "%s".', variant);
end
end


function w = localFeatherWeights(n, featherPx)
w = ones(1,n);
f = min(featherPx, floor(n/2));
if f > 0
    ramp = linspace(0,1,f);
    w(1:f) = ramp;
    w(end-f+1:end) = fliplr(ramp);
end
end
