function [orientation, swapXY] = chooseTileCorrection(r, omeMeta, seriesIdx, tileAnchor, nChannels, verbose)
% =========================================
% Script: chooseTileCorrection.m
% Created: 2026-08-26
% Purpose: Picks the tile-orientation and X/Y-position-swap correction
%          for a mosaic group by testing every {channel x swapXY}
%          combination and taking the single most confident result
%          overall, then applying that same correction to every channel.
%
%          A multi-channel tile shares one physical scan head - all
%          channels are read out from the same raster position at the
%          same time, so they must share the same true correction. But
%          different channels can have very different signal quality
%          (a dim reference channel vs a bright functional one), so
%          detecting independently per channel and trusting only
%          channel 1 (an earlier version of this code did that) can
%          settle on a weak, low-confidence answer from a noisy channel
%          when a much clearer signal was available from another one.
%
% Inputs:
%   r, omeMeta   - open Bio-Formats reader/metadata store
%   seriesIdx    - 0-based series indices for this mosaic group
%   tileAnchor   - 'center' or 'corner' (see getTileGeometry.m)
%   nChannels    - number of channels this group has
%   verbose      - true/false, print progress
% Outputs:
%   orientation  - 'none'/'fliplr'/'flipud'/'rot180'
%   swapXY       - logical
% Last modified: 2026-08-26 - initial version
% =========================================

bestConf = -Inf;
orientation = 'none';
swapXY = false;

for doSwap = [false true]
    geom = getTileGeometry(r, omeMeta, seriesIdx, tileAnchor, doSwap);
    for ch = 1:nChannels
        planes = readResampledPlanes(r, seriesIdx, ch, geom.pxX, geom.outPxSize);
        [var, conf] = detectTileOrientation(planes, geom.left_um, geom.top_um, ...
            geom.right_um, geom.bottom_um, geom.outPxSize, false);
        if verbose
            fprintf('[chooseTileCorrection]   swapXY=%d channel=%d -> "%s" (confidence=%.3f)\n', ...
                doSwap, ch, var, conf);
        end
        if conf > bestConf
            bestConf = conf;
            orientation = var;
            swapXY = doSwap;
        end
    end
end

if verbose
    fprintf('[chooseTileCorrection] chosen: orientation="%s" swapXY=%d (confidence=%.3f)\n', ...
        orientation, swapXY, bestConf);
end

end
