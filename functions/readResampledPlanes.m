function planes = readResampledPlanes(r, seriesIdx, ch, pxX, outPxSize)
% =========================================
% Script: readResampledPlanes.m
% Created: 2026-08-26
% Purpose: Reads one channel's plane from each of a set of tile series,
%          resampling each to a common output pixel size so tiles
%          acquired at different resolutions can be placed on one canvas.
% Inputs:
%   r          - open Bio-Formats reader
%   seriesIdx  - 0-based series indices to read (row/col vector)
%   ch         - 1-based channel index to read from each series
%   pxX        - per-tile physical pixel size (um), same order as seriesIdx
%   outPxSize  - target pixel size (um) to resample every tile to
% Outputs:
%   planes     - cell array of 2D single arrays, one per series
% Last modified: 2026-08-26 - initial version
% =========================================

nTiles = numel(seriesIdx);
planes = cell(nTiles,1);
for i = 1:nTiles
    r.setSeries(seriesIdx(i));
    plane = single(readPlaneWithRetry(r, 1, ch, 1));
    scale = pxX(i) / outPxSize;
    if abs(scale-1) > 1e-3
        plane = imresize(plane, scale, 'bilinear');
    end
    planes{i} = plane;
end

end
