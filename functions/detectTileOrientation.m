function [bestVariant, confidence] = detectTileOrientation(planes, left_um, top_um, right_um, bottom_um, outPxSize, verbose)
% =========================================
% Script: detectTileOrientation.m
% Created: 2026-08-26
% Purpose: Empirically determines whether each tile's pixel data needs
%          flipping before it matches its own stage-position metadata.
%          Some Leica/Bio-Formats confocal readers return tile pixel
%          arrays that are mirrored/rotated relative to the stage X/Y
%          axes used for PlanePosition - if uncorrected, tiles land in
%          the right grid cells but their CONTENT doesn't line up across
%          seams (structures don't connect, even though there are no
%          gaps in coverage).
%
%          This is tested directly on the real data: for pairs of
%          bright, genuinely-overlapping neighbouring tiles (found from
%          their actual stage positions/sizes, so this works for a
%          regular grid spiral or an irregular/manually-revisited tile
%          set), the true overlapping edge strips are correlated under
%          each of {none, fliplr, flipud, rot180}. Whichever orientation
%          wins the most pairs is returned. This is a DIFFERENT, and
%          independent, correction from a possible X/Y position-field
%          swap (see getTileGeometry.m's swapXY) - the caller should run
%          this once per swapXY hypothesis (on the same read planes,
%          just different left/top/right/bottom) and compare the
%          returned confidence to pick the overall best combination.
%
% Inputs:
%   planes     - cell array of 2D single tile images, ALREADY resampled
%                to outPxSize, one channel only (orientation is assumed
%                the same for every channel of a mosaic)
%   left_um, top_um, right_um, bottom_um - per-tile physical bounding
%                box (um), same order as planes
%   outPxSize  - output pixel size (um/px), used to size overlap strips
%   verbose    - true/false, print the vote tally
% Outputs:
%   bestVariant - one of 'none','fliplr','flipud','rot180'
%   confidence  - sum of the NCC values of the pairs that voted for
%                 bestVariant (0 if no qualifying pairs were found) -
%                 rewards both agreement count and match strength, so
%                 it's comparable across different geometry hypotheses
% Last modified: 2026-08-26 - added confidence output so the caller can
%                compare across a swapXY hypothesis too
% =========================================

if ~iscell(planes) || numel(planes) < 2
    bestVariant = 'none';
    confidence = 0;
    return
end

n = numel(planes);
meanI = cellfun(@(p) mean(p(:), 'omitnan'), planes);
[~, order] = sort(meanI, 'descend');
cand = order(1:min(60,n));

variants = {'none','fliplr','flipud','rot180'};
votes = zeros(1,4);
nccSum = zeros(1,4);
nPairsUsed = 0;
maxPairs = 15;

for a = 1:numel(cand)
    for b = a+1:numel(cand)
        ia = cand(a); ib = cand(b);
        wA = right_um(ia)-left_um(ia); hA = bottom_um(ia)-top_um(ia);
        ox = min(right_um(ia),right_um(ib)) - max(left_um(ia),left_um(ib));
        oy = min(bottom_um(ia),bottom_um(ib)) - max(top_um(ia),top_um(ib));

        if oy > 0.85*hA && ox > 0.03*wA && ox < 0.5*wA
            kind = 'h';
        elseif ox > 0.85*wA && oy > 0.03*hA && oy < 0.5*hA
            kind = 'v';
        else
            continue
        end

        if strcmp(kind,'h')
            if left_um(ia) < left_um(ib), L=ia; R=ib; else, L=ib; R=ia; end
            overlap_um = right_um(L) - left_um(R);
            overlapPx = max(4, round(overlap_um/outPxSize));
            overlapPx = min(overlapPx, floor(0.4*size(planes{L},2)));
        else
            if top_um(ia) < top_um(ib), T=ia; B=ib; else, T=ib; B=ia; end
            overlap_um = bottom_um(T) - top_um(B);
            overlapPx = max(4, round(overlap_um/outPxSize));
            overlapPx = min(overlapPx, floor(0.4*size(planes{T},1)));
        end
        if overlapPx < 4, continue; end

        nccByVariant = nan(1,4);
        for v = 1:4
            switch kind
                case 'h'
                    [pL, pR] = applyOrientation2(planes{L}, planes{R}, variants{v});
                    stripL = pL(:, end-overlapPx+1:end);
                    stripR = pR(:, 1:overlapPx);
                    nRows = min(size(stripL,1), size(stripR,1));
                    if nRows < 4, continue; end
                    nccByVariant(v) = corr2(stripL(1:nRows,:), stripR(1:nRows,:));
                case 'v'
                    [pT, pB] = applyOrientation2(planes{T}, planes{B}, variants{v});
                    stripT = pT(end-overlapPx+1:end, :);
                    stripB = pB(1:overlapPx, :);
                    nCols = min(size(stripT,2), size(stripB,2));
                    if nCols < 4, continue; end
                    nccByVariant(v) = corr2(stripT(:,1:nCols), stripB(:,1:nCols));
            end
        end
        [bestNcc, w] = max(nccByVariant);
        if bestNcc > 0.1   % only count pairs with a genuinely confident winner
            votes(w) = votes(w) + 1;
            nccSum(w) = nccSum(w) + bestNcc;
            nPairsUsed = nPairsUsed + 1;
        end
        if nPairsUsed >= maxPairs, break; end
    end
    if nPairsUsed >= maxPairs, break; end
end

if nPairsUsed == 0
    bestVariant = 'none';
    confidence = 0;
    if verbose
        warning('detectTileOrientation:noPairs', ...
            'No confidently-correlating neighbour pairs found; leaving tile orientation unchanged. Check the stitched output for broken structures across seams.');
    end
else
    [~, wi] = max(votes);
    bestVariant = variants{wi};
    confidence = nccSum(wi);
    if verbose
        fprintf('[detectTileOrientation] votes over %d pair(s) [none,fliplr,flipud,rot180] = %s -> using "%s" (confidence=%.3f)\n', ...
            nPairsUsed, mat2str(votes), bestVariant, confidence);
    end
end

end


function [pA, pB] = applyOrientation2(rawA, rawB, variant)
switch variant
    case 'none',   pA = rawA;          pB = rawB;
    case 'fliplr', pA = fliplr(rawA);  pB = fliplr(rawB);
    case 'flipud', pA = flipud(rawA);  pB = flipud(rawB);
    case 'rot180', pA = rot90(rawA,2); pB = rot90(rawB,2);
end
end
