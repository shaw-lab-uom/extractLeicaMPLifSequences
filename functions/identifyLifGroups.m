function groups = identifyLifGroups(r, omeMeta)
% =========================================
% Script: identifyLifGroups.m
% Created: 2026-08-26
% Purpose: Groups the series of an open Bio-Formats reader into the
%          logical scans a LAS X project actually contains.
%
%          LAS X Navigator tile scans (spirals etc.) that were saved
%          without ticking "merge tiles" store every individual field as
%          its own series, named "<scanName>/Preview/Preview <N>" - and
%          because a live scan gets interrupted/restarted (refocus,
%          channel change, zoom change, pause) LAS X splits what is
%          really ONE acquisition across several different "Preview N"
%          sub-folders, while ALSO leaving behind an unrelated shared
%          low-mag single-channel navigator reference grid under the
%          same scan name. Picking just the single largest "Preview N"
%          subset (as an earlier version of this code did) silently
%          grabs that reference grid instead of real multi-channel data.
%
%          Instead: all tiles sharing a scan name are pooled and then
%          split by channel count (sizeC) - this cleanly separates a
%          single-channel reference pass from the real acquisition data
%          without needing to trust LAS X's "Preview N" bookkeeping, and
%          unions tiles fragmented across multiple Preview N sub-folders
%          back into one mosaic.
%
% Inputs:
%   r       - open loci.formats.IFormatReader (via bfGetReader)
%   omeMeta - r.getMetadataStore()
% Outputs:
%   groups  - struct array, one row per logical scan to export, fields:
%       .name      - sanitized name to use in output filenames
%       .seriesIdx - 0-based Bio-Formats series indices belonging to this group
%       .isMosaic  - true if this group has >1 tile requiring stitching
%       .nChannels - channel count of this group (all its tiles share it)
% Last modified: 2026-08-26 - rewritten to cluster by channel count
%                instead of picking the single largest Preview N subset;
%                then, within each channel-count cluster, each exact
%                "Preview N" label is folded into the main mosaic only if
%                it BOTH extends the covered area AND sits physically
%                adjacent to the main group's own tile spacing, so a
%                zoom-in/repeat sub-scan no longer corrupts the mosaic,
%                and neither does an isolated single stray tile (which,
%                alone, is trivially always "outside the box" no matter
%                how far away it is - confirmed visually as a
%                disconnected tile sitting alone in a corner before this
%                adjacency check was added) - see resolveMosaicByCoverage
% =========================================

if ~isa(r, 'loci.formats.IFormatReader')
    error('identifyLifGroups:invalidReader', 'r must be an open Bio-Formats reader (bfGetReader).');
end

nSeries = r.getSeriesCount();
names = strings(nSeries,1);
for s = 0:nSeries-1
    names(s+1) = string(char(omeMeta.getImageName(s)));
end

isTile = false(nSeries,1);
baseName = strings(nSeries,1);
previewNum = nan(nSeries,1);
for s = 1:nSeries
    tok = regexp(char(names(s)), '^(.*)/Preview/Preview (\d+)$', 'tokens', 'once');
    if ~isempty(tok)
        isTile(s) = true;
        baseName(s) = tok{1};
        previewNum(s) = str2double(tok{2});
    end
end

sizeC = nan(nSeries,1);
posX = nan(nSeries,1); posY = nan(nSeries,1);
pxSizeX = nan(nSeries,1);
for s0 = find(isTile)' - 1
    r.setSeries(s0);
    sizeC(s0+1) = r.getSizeC();
    posX(s0+1) = double(omeMeta.getPlanePositionX(s0,0).value().doubleValue());
    posY(s0+1) = double(omeMeta.getPlanePositionY(s0,0).value().doubleValue());
    pxSizeX(s0+1) = double(omeMeta.getPixelsPhysicalSizeX(s0).value().doubleValue());
end

groups = struct('name', {}, 'seriesIdx', {}, 'isMosaic', {}, 'nChannels', {}, 'baseNameRaw', {});

% --- Tile-scan groups: pool by scan name, split by channel count, then
% treat each exact "Preview N" label as a candidate sub-scan and decide
% whether to fold it into the main mosaic or keep it separate based on
% whether it actually EXTENDS the covered area or just duplicates
% coverage already there.
%
% Naively unioning every "Preview N" sharing a (scan name, channel count)
% - an earlier version of this code did this - gets confused two
% opposite ways LAS X produces multiple Preview N labels under one scan:
%   (a) a live scan interrupted/restarted (refocus, pause) fragments ONE
%       real acquisition across several Preview N labels that together
%       extend coverage - these genuinely belong in one mosaic;
%   (b) a zoom-in/repeat scan of one ROI, revisiting a region already
%       covered by the main grid - unioning this in corrupts the main
%       mosaic with a cluster of overlapping tiles at the wrong scale
%       sitting in the middle of it (confirmed here by plotting tiles in
%       acquisition order: the revisit tiles are LATER, and jump
%       incoherently inside the area the earlier, systematic tiles
%       already swept - not part of the same spiral at all).
%
% Distinguishing (a) from (b): start from the largest Preview-N label as
% the seed, then fold in each other label, largest first, only if most
% of ITS tiles fall outside the area already covered - i.e. it extends
% the mosaic rather than just re-visiting it.
uBase = unique(baseName(isTile));
for i = 1:numel(uBase)
    b = uBase(i);
    memberIdx1 = find(isTile & baseName == b);   % 1-based into names/sizeC/posX/posY/previewNum
    uC = unique(sizeC(memberIdx1));
    for c = 1:numel(uC)
        thisC = uC(c);
        sel1 = memberIdx1(sizeC(memberIdx1) == thisC);

        if numel(uC) > 1
            grpTag = sprintf('_%dch', thisC);
        else
            grpTag = '';
        end

        % Only the main, coverage-extending group is exported. Rejected
        % labels (revisits/zoom-ins that don't extend the covered area -
        % see resolveMosaicByCoverage) are discarded outright rather than
        % written out as their own "_sub"/"_snapshot" files: they're
        % redundant with the main mosaic, and exporting dozens of extra
        % files per scan just to hold data already represented in the
        % main image is more clutter than it's worth.
        mainIdx1 = resolveMosaicByCoverage(sel1, previewNum, posX, posY);

        % Final cleanup: a manually-clicked ROI tile set (not an
        % automated grid/spiral) can contain individual tiles with a
        % stray, unrelated position WITHIN a single Preview-N label - the
        % coverage-vs-adjacency check above only decides whether to fold
        % in a whole label, so it can't catch an outlier tile sitting
        % inside the very label it seeded the mosaic from (confirmed
        % visually: an isolated tile floating alone in a corner,
        % disconnected from the rest of the image). Keep only the
        % largest spatially-connected component of the assembled set.
        comp = clusterTilesBySpatialCoherence(posX(mainIdx1), posY(mainIdx1));
        mainIdx1 = mainIdx1(comp == 1);

        groups(end+1) = struct('name', [sanitizeFileName(b) grpTag], ...
            'seriesIdx', mainIdx1 - 1, 'isMosaic', numel(mainIdx1) > 1, 'nChannels', thisC, ...
            'baseNameRaw', char(b)); %#ok<AGROW>
    end
end

% --- Standalone series (not part of any tile scan) ---
standaloneIdx1 = find(~isTile);
for i = 1:numel(standaloneIdx1)
    s1 = standaloneIdx1(i);
    r.setSeries(s1-1);
    groups(end+1) = struct('name', sanitizeFileName(names(s1)), ...
        'seriesIdx', s1-1, 'isMosaic', false, 'nChannels', r.getSizeC(), 'baseNameRaw', ''); %#ok<AGROW>
end

% --- De-duplicate output names (append _2, _3, ... on collision) ---
allNames = string({groups.name});
for i = 1:numel(groups)
    dupCount = sum(allNames(1:i-1) == allNames(i));
    if dupCount > 0
        groups(i).name = sprintf('%s_%d', groups(i).name, dupCount+1);
    end
end

end


function mainIdx1 = resolveMosaicByCoverage(sel1, previewNum, posX, posY)
% Groups sel1 (1-based indices into the metadata arrays) by their exact
% "Preview N" label, then greedily folds each label (largest first) into
% a growing "main" bounding box only if most of its tiles fall outside
% the area already covered - i.e. it extends the mosaic rather than
% re-visiting ground already covered by a bigger label. Labels that
% don't qualify (revisits/zoom-ins of a spot already covered) are
% dropped - see the caller for why they aren't exported separately.
%
% Inputs:  sel1       - 1-based indices (into posX/posY/previewNum) for
%                       one (scan name, channel count) cluster
%          previewNum, posX, posY - full-length arrays, indexed by sel1
% Outputs: mainIdx1    - 1-based indices making up the main mosaic

pn = previewNum(sel1);
uPn = unique(pn);
labelCounts = arrayfun(@(v) sum(pn==v), uPn);
[~, order] = sort(labelCounts, 'descend');
uPn = uPn(order);

mainSel1 = sel1(pn == uPn(1));
mainLeft = min(posX(mainSel1)); mainRight = max(posX(mainSel1));
mainTop  = min(posY(mainSel1)); mainBottom = max(posY(mainSel1));

% Typical tile-to-tile spacing within the main group. "Falls outside the
% current bounding box" alone isn't enough to call something a genuine
% extension: a single stray tile with an unrelated position is trivially
% ALWAYS outside the box no matter how far away it is (there's nothing to
% average over) - it would pass that test and get merged in as an
% isolated island (confirmed visually: an unrelated tile sitting alone in
% a corner, disconnected from the rest of the mosaic). Also requiring the
% candidate to sit near the main group's own tile spacing - i.e. it
% physically continues the grid rather than just existing somewhere else
% in stage-coordinate space - rules that out.
if numel(mainSel1) >= 2
    D = hypot(posX(mainSel1)-posX(mainSel1)', posY(mainSel1)-posY(mainSel1)');
    D(1:size(D,1)+1:end) = Inf;
    mainStep = median(min(D,[],2));
else
    mainStep = Inf;   % can't estimate spacing from one tile - skip the proximity check
end
proximityLimit = 3 * mainStep;

for i = 2:numel(uPn)
    candSel1 = sel1(pn == uPn(i));
    outside = posX(candSel1) < mainLeft | posX(candSel1) > mainRight | ...
              posY(candSel1) < mainTop  | posY(candSel1) > mainBottom;

    distToMain = hypot(posX(candSel1)-posX(mainSel1)', posY(candSel1)-posY(mainSel1)');
    isAdjacent = min(distToMain(:)) <= proximityLimit;

    if mean(outside) > 0.5 && isAdjacent
        mainSel1 = [mainSel1; candSel1]; %#ok<AGROW>
        mainLeft = min(mainLeft, min(posX(candSel1)));
        mainRight = max(mainRight, max(posX(candSel1)));
        mainTop = min(mainTop, min(posY(candSel1)));
        mainBottom = max(mainBottom, max(posY(candSel1)));
    end
end

mainIdx1 = mainSel1;

end
