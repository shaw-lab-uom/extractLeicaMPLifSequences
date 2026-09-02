function summary = lifToTiffs(lifDir, lifFileName, varargin)
% =========================================
% Script: lifToTiffs.m
% Created: 2026-08-26
% Purpose: General-purpose Leica .lif exporter. Opens any .lif file and
%          writes every distinct scan/recording inside it out to the
%          same folder as the .lif, so you never need to open the .lif
%          in ImageJ/LAS X just to get images out of it:
%            - Unmerged tile-scan mosaics (e.g. a Navigator spiral saved
%              without ticking "merge") are stitched into one image using
%              stage-position metadata. Tile pixel data is checked against
%              a known Leica/Bio-Formats quirk where a tile's pixel array
%              can be mirrored/rotated - and its stage-position fields can
%              be mislabelled - relative to its true position (detected
%              empirically from the real tile overlaps, whichever channel
%              gives the clearest signal - see detectTileOrientation.m/
%              chooseTileCorrection.m - not assumed), then exposure-
%              matched, flat-field corrected, and blended. Written as an
%              8-bit, contrast-stretched PNG (writeSpiralPNG.m), not a
%              calibrated TIFF: these mosaics are dim by nature and used
%              for visual reference, not quantitative measurement, and a
%              plain 16-bit TIFF opens looking black in most viewers
%              until manually contrast-adjusted.
%            - Already-merged tile scans / single snapshots are saved as
%              a calibrated TIFF, unchanged.
%            - Z-stacks are saved as multi-page calibrated TIFFs (one
%              page per slice).
%            - Time series / movies are saved as multi-page calibrated
%              TIFFs (one page per frame).
%            - Multi-channel data is split into one file per channel
%              (suffixed _C1, _C2, ...).
%          A zoom-in/repeat sub-scan of a region already covered by the
%          main tile-scan grid (LAS X can tag these with the same scan
%          name) is detected and excluded from the mosaic rather than
%          corrupting it - see identifyLifGroups.m.
%
% Inputs:
%   lifDir      - folder containing the .lif file
%   lifFileName - .lif file name, e.g. '250826_ecGCaMP.lif'
%   Name-Value pairs:
%     'OutDir'         - output folder (default: same as lifDir)
%     'TileAnchor'     - 'center' (default) or 'corner': whether a
%                        tile's stage position is its centre or top-left
%                        corner.
%     'FeatherPx'      - feather blend width in output px for mosaics (default 40)
%     'FlatField'      - true (default) or false: correct per-tile
%                        brightness variation in mosaics using a
%                        self-estimated flat field
%     'TileOrientation'- 'auto' (default): empirically detect, once per
%                        scan name, whether tiles need flipping to match
%                        their stage position (see detectTileOrientation.m).
%                        Or force a fixed 'none'/'fliplr'/'flipud'/'rot180'
%                        for every mosaic if you already know your rig's
%                        quirk and want to skip detection.
%     'Verbose'        - true (default) or false
%
% Outputs:
%   summary - table, one row per exported group, with columns:
%             name, type ('mosaic'/'single'), nTiles, orientation, files (cellstr)
%   Also writes the image files themselves to OutDir, named
%   '<lifFileName>_<scanName>_<YYYYMMDD>[_C#].png' for a mosaic, or
%   '<lifFileName>_<scanName>_<YYYYMMDD>[_C#].tif' for anything else
%
% Example:
%   lifToTiffs('Z:\RawDataStore\TwoPhoton\ecGCaMP_imaging\25082026', ...
%       '250826_ecGCaMP.lif');
%
% Last modified: 2026-08-26 - fixed tile-set selection to cluster by
%                channel count (was silently picking a single-channel
%                navigator reference pass over real multi-channel data);
%                orientation/swapXY correction is chosen from whichever
%                {channel, swapXY} combination gives the single highest-
%                confidence answer (see chooseTileCorrection.m) rather
%                than from channel 1 alone, since a multi-channel mosaic
%                shares one scan head so all channels must share the
%                true correction, but channels can differ hugely in
%                signal quality; mosaics now write as contrast-stretched
%                PNGs (writeSpiralPNG.m) instead of calibrated TIFFs, so
%                they look right in any viewer without manual contrast
%                adjustment; also added per-tile intensity matching,
%                flat-field normalisation, ImageJ-calibrated TIFF
%                metadata for non-mosaic outputs, and retries for
%                transient network I/O errors
% =========================================

p = inputParser;
addRequired(p, 'lifDir', @(x) (ischar(x) || isstring(x)) && isfolder(x));
addRequired(p, 'lifFileName', @(x) ischar(x) || isstring(x));
addParameter(p, 'OutDir', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'TileAnchor', 'center', @(x) ismember(x, {'center','corner'}));
addParameter(p, 'FeatherPx', 40, @(x) isnumeric(x) && isscalar(x) && x>=0);
addParameter(p, 'FlatField', true, @(x) islogical(x) && isscalar(x));
addParameter(p, 'TileOrientation', 'auto', @(x) ismember(x, {'auto','none','fliplr','flipud','rot180'}));
addParameter(p, 'Verbose', true, @(x) islogical(x) && isscalar(x));
parse(p, lifDir, lifFileName, varargin{:});
opt = p.Results;

lifPath = fullfile(char(opt.lifDir), char(opt.lifFileName));
if ~isfile(lifPath)
    error('lifToTiffs:fileNotFound', 'LIF file not found: %s', lifPath);
end
[~, lifBase] = fileparts(char(opt.lifFileName));

outDir = char(opt.OutDir);
if isempty(outDir), outDir = char(opt.lifDir); end
if ~isfolder(outDir)
    mkdir(outDir);
end

if isempty(which('bfGetReader'))
    error('lifToTiffs:bioformatsMissing', ...
        ['Bio-Formats MATLAB toolbox (bfmatlab) not found on the path. ' ...
         'Download it from https://www.openmicroscopy.org/bio-formats/downloads/ and addpath it.']);
end

% Opening a multi-GB file over a network share (e.g. a mapped drive) can
% hit a transient "file not found" / I/O error even though the file is
% perfectly fine - retry a few times before giving up.
r = [];
lastOpenErr = [];
for attempt = 1:4
    try
        r = bfGetReader(lifPath);
        break
    catch ME
        lastOpenErr = ME;
        if attempt < 4, pause(2 * attempt); end
    end
end
if isempty(r)
    error('lifToTiffs:openFailed', 'Failed to open %s after 4 attempts: %s', lifPath, lastOpenErr.message);
end
cleanupObj = onCleanup(@() r.close());
omeMeta = r.getMetadataStore();

groups = identifyLifGroups(r, omeMeta);
dateStr = datestr(now, 'yyyymmdd');

if opt.Verbose
    fprintf('[lifToTiffs] %s: found %d scan(s) to export.\n', lifPath, numel(groups));
end

% --- Resolve tile orientation AND the X/Y position-field swap (a
% documented Bio-Formats LIF quirk - see getTileGeometry.m) independently
% for EACH mosaic group (see chooseTileCorrection.m). A multi-channel
% mosaic shares one physical scan head, so every channel must share the
% same true correction - but channels can differ hugely in signal
% quality, so the choice is made from whichever {channel, swapXY}
% combination gives the single highest-confidence answer, not from
% channel 1 alone (channel 1 can be a much weaker/noisier signal than
% another channel in the same tile).
orientationByGroup = strings(numel(groups),1);
swapXYByGroup = false(numel(groups),1);
if strcmpi(opt.TileOrientation, 'auto')
    for g = 1:numel(groups)
        if ~groups(g).isMosaic, continue; end
        grp = groups(g);
        if opt.Verbose
            fprintf('[lifToTiffs] "%s":\n', grp.name);
        end
        [orientationByGroup(g), swapXYByGroup(g)] = chooseTileCorrection(...
            r, omeMeta, grp.seriesIdx, opt.TileAnchor, grp.nChannels, opt.Verbose);
    end
end

names = strings(numel(groups),1);
types = strings(numel(groups),1);
nTilesCol = zeros(numel(groups),1);
orientCol = strings(numel(groups),1);
filesCol = cell(numel(groups),1);

for g = 1:numel(groups)
    grp = groups(g);
    outFileBase = fullfile(outDir, sprintf('%s_%s_%s', lifBase, grp.name, dateStr));

    if grp.isMosaic
        if strcmpi(opt.TileOrientation, 'auto')
            thisOrientation = char(orientationByGroup(g));
            thisSwapXY = swapXYByGroup(g);
        else
            thisOrientation = opt.TileOrientation;
            thisSwapXY = false;
        end
        exportOpts = struct('TileAnchor', opt.TileAnchor, 'FeatherPx', opt.FeatherPx, ...
            'FlatField', opt.FlatField, 'TileOrientation', thisOrientation, ...
            'SwapXY', thisSwapXY, 'Verbose', opt.Verbose);
        try
            nTiles = stitchTileGroup(r, omeMeta, grp.seriesIdx, outFileBase, exportOpts);
            types(g) = "mosaic";
            nTilesCol(g) = nTiles;
            if thisSwapXY
                orientCol(g) = thisOrientation + "+swapXY";
            else
                orientCol(g) = thisOrientation;
            end
        catch ME
            warning('lifToTiffs:mosaicFailed', 'Skipping "%s" (mosaic stitch failed): %s', grp.name, ME.message);
            names(g) = grp.name; types(g) = "FAILED"; filesCol{g} = {};
            continue
        end
    else
        exportOpts = struct('Verbose', opt.Verbose);
        exportLifSeries(r, omeMeta, grp.seriesIdx, outFileBase, exportOpts);
        types(g) = "single";
        nTilesCol(g) = 1;
    end
    names(g) = grp.name;
    filePattern = sprintf('%s_%s_%s*', lifBase, grp.name, dateStr);
    if grp.isMosaic
        filesCol{g} = dirMatch(outDir, [filePattern '.png']);   % mosaics: see writeSpiralPNG.m
    else
        filesCol{g} = dirMatch(outDir, [filePattern '.tif']);
    end
end

summary = table(names, types, nTilesCol, orientCol, filesCol, ...
    'VariableNames', {'name','type','nTiles','orientation','files'});
if opt.Verbose
    disp(summary(:, {'name','type','nTiles','orientation'}));
    fprintf('[lifToTiffs] Done. %d scan(s) written to %s\n', numel(groups), outDir);
end

end


function files = dirMatch(folder, pattern)
d = dir(fullfile(folder, pattern));
if isempty(d)
    files = {};
else
    files = fullfile({d.folder}, {d.name})';
end
end
