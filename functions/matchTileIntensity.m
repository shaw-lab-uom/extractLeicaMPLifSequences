function planesOut = matchTileIntensity(planesIn, verbose)
% =========================================
% Script: matchTileIntensity.m
% Created: 2026-08-26
% Purpose: Rescales each tile by a single per-tile scalar so every tile
%          shares a common robust brightness level (its 99th-percentile
%          intensity). LAS X's live-scan auto-exposure can drift the
%          gain/offset of individual tiles over the course of a spiral
%          (neighbouring, temporally-adjacent tiles sharing a similar
%          drift), which shows up as visible banding/blocks of brighter
%          or darker tiles once assembled. This is a per-tile SCALE
%          difference, not a shared spatial vignette pattern, so it is
%          not fixed by estimateFlatField/applyFlatField (which corrects
%          only the smooth illumination pattern common to every tile) -
%          run this first, then flat-field the result.
% Inputs:  planesIn - cell array of 2D numeric arrays (any/mixed sizes)
%          verbose  - true/false, print the scale factor range (default false)
% Outputs: planesOut - cell array, same sizes, intensity-matched
% Last modified: 2026-08-26 - clamp scale factors to a sane range so a
%                genuinely blank/background tile (near-zero signal,
%                correctly dark) doesn't get blown up trying to match
%                brightness with tiles that have real content
% =========================================

if nargin < 2, verbose = false; end
if ~iscell(planesIn) || isempty(planesIn)
    error('matchTileIntensity:invalidInput', 'planesIn must be a non-empty cell array.');
end

n = numel(planesIn);
levels = zeros(n,1);
for i = 1:n
    levels(i) = prctile(double(planesIn{i}(:)), 99);
end

% A tile with essentially no signal has nothing to correct - leave it
% alone rather than let a near-zero denominator blow its scale factor up
% into amplified noise. Only tiles with a genuine, meaningful level
% relative to the group are considered when picking the common target
% and when computing their own scale factor.
noiseFloor = max(prctile(levels, 10), 1);
hasSignal = levels >= noiseFloor;
if nnz(hasSignal) < 2
    planesOut = planesIn;
    if verbose
        fprintf('[matchTileIntensity] too few tiles with real signal - skipping intensity matching\n');
    end
    return
end
target = median(levels(hasSignal));

planesOut = cell(size(planesIn));
scales = ones(n,1);
scales(hasSignal) = target ./ levels(hasSignal);
% Asymmetric clamp: pulling an over-bright tile DOWN never invents signal,
% so that direction is allowed a wide range; pushing a dim tile UP can
% amplify noise into false signal, so that direction stays conservative.
scales = min(max(scales, 0.03), 3);
for i = 1:n
    planesOut{i} = planesIn{i} * scales(i);
end

if verbose
    fprintf('[matchTileIntensity] per-tile scale factors range [%.3g, %.3g] (target level=%.4g)\n', ...
        min(scales), max(scales), target);
end

end
