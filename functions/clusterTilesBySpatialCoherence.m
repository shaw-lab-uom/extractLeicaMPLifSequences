function componentIdx = clusterTilesBySpatialCoherence(posX, posY)
% =========================================
% Script: clusterTilesBySpatialCoherence.m
% Created: 2026-08-26
% Purpose: Splits a set of tile centre positions into connected
%          components that share a consistent step size - i.e. the
%          actual tiled grid/spiral a tile belongs to. LAS X can leave
%          several DIFFERENT sub-scans (the main tile-scan grid, plus
%          smaller zoom-in/repeat scans of one ROI within it) tagged
%          with the same scan name and channel count; grouping by
%          channel count alone silently merges these together, which
%          corrupts the main mosaic with a cluster of overlapping tiles
%          at the wrong scale sitting in the middle of it.
%
%          Method: find each tile's nearest-neighbour distance, take the
%          mode as the dominant grid step, then connect any two tiles
%          whose separation is within a tolerance of that step. Distance
%          is invariant to an X/Y position-field swap, so this works
%          regardless of that correction (see getTileGeometry.m).
%
% Inputs:  posX, posY - raw tile centre positions (any consistent unit),
%          column vectors, same order
% Outputs: componentIdx - integer label per tile (1 = largest component,
%          i.e. the main grid; higher numbers = smaller components,
%          ordered largest to smallest)
% Last modified: 2026-08-26 - initial version
% =========================================

n = numel(posX);
if n < 2
    componentIdx = ones(n,1);
    return
end

D = hypot(posX - posX', posY - posY');
D(1:n+1:end) = Inf;   % ignore self-distance
nnDist = min(D, [], 2);
gridStep = mode(round(nnDist / 5) * 5);   % round to nearest 5 units before taking the mode
if gridStep <= 0
    gridStep = median(nnDist);
end

adj = D <= gridStep * 1.4;   % generous tolerance for jitter/diagonal steps

% Connected components via simple flood fill (union-find would scale
% better, but tile counts here are in the hundreds at most).
labels = zeros(n,1);
nextLabel = 0;
for i = 1:n
    if labels(i) ~= 0, continue; end
    nextLabel = nextLabel + 1;
    stack = i;
    labels(i) = nextLabel;
    while ~isempty(stack)
        cur = stack(end); stack(end) = [];
        nbrs = find(adj(cur,:) & labels' == 0);
        labels(nbrs) = nextLabel;
        stack = [stack, nbrs]; %#ok<AGROW>
    end
end

% Relabel so component 1 is the largest.
counts = accumarray(labels, 1);
[~, order] = sort(counts, 'descend');
remap = zeros(numel(counts),1);
remap(order) = 1:numel(counts);
componentIdx = remap(labels);

end
