function exportLifSeries(r, omeMeta, seriesIdx, outFileBase, opts)
% =========================================
% Script: exportLifSeries.m
% Created: 2026-08-26
% Purpose: Exports one standard (non-mosaic) Bio-Formats series to one
%          ImageJ-compatible multi-page TIFF per channel. Time frames
%          and Z slices (if present) are written as successive pages,
%          in T-major order - so an XYT movie becomes an XY-by-frame
%          stack, a Z-stack becomes an XY-by-slice stack, and a plain
%          2D image becomes a single-page TIFF. Pixel size, Z-step, and
%          frame interval (whichever apply) are embedded using ImageJ's
%          own TIFF metadata convention (see writeImageJTiff.m) so they
%          come back calibrated automatically when reopened - no need
%          to re-enter them by hand.
%
% Inputs:
%   r           - open Bio-Formats reader
%   omeMeta     - r.getMetadataStore()
%   seriesIdx   - scalar 0-based series index to export
%   outFileBase - full output path WITHOUT extension (channel suffix and
%                 .tif extension are appended here)
%   opts        - struct with field Verbose (logical)
% Last modified: 2026-08-26 - embeds pixel size / Z-step / frame interval
%                using ImageJ-convention TIFF tags (imagejTagStruct);
%                retries transient network read errors
%                (readPlaneWithRetry); keeps one Tiff handle open across
%                all pages of a channel instead of reopening per frame
%                (was the dominant cost on multi-thousand-frame recordings)
% =========================================

if ~(isnumeric(seriesIdx) && isscalar(seriesIdx) && seriesIdx >= 0)
    error('exportLifSeries:invalidSeriesIdx', 'seriesIdx must be a single non-negative integer.');
end

r.setSeries(seriesIdx);
sizeX = r.getSizeX(); sizeY = r.getSizeY();
sizeZ = r.getSizeZ(); sizeC = r.getSizeC(); sizeT = r.getSizeT();

pxSizeXY = [];
try
    pxSizeXY = double(omeMeta.getPixelsPhysicalSizeX(seriesIdx).value().doubleValue());
catch
end

pxSizeZ = [];
if sizeZ > 1
    try
        pxSizeZ = double(omeMeta.getPixelsPhysicalSizeZ(seriesIdx).value().doubleValue());
    catch
    end
end

frameIntervalSec = [];
if sizeT > 1
    try
        frameIntervalSec = double(omeMeta.getPixelsTimeIncrement(seriesIdx).value().doubleValue());
    catch
        % Fall back to the gap between the first two frames' timestamps,
        % since not every format/version reports a single constant
        % TimeIncrement even when frames are evenly spaced.
        try
            t0 = double(omeMeta.getPlaneDeltaT(seriesIdx, 0).value().doubleValue());
            t1 = double(omeMeta.getPlaneDeltaT(seriesIdx, r.getIndex(0,0,1)).value().doubleValue());
            frameIntervalSec = t1 - t0;
        catch
        end
    end
end

if opts.Verbose
    fprintf('[exportLifSeries] "%s": %dx%d, Z=%d C=%d T=%d', outFileBase, sizeX, sizeY, sizeZ, sizeC, sizeT);
    if ~isempty(pxSizeXY), fprintf(', pxSize=%.4gum', pxSizeXY); end
    if ~isempty(pxSizeZ), fprintf(', zStep=%.4gum', pxSizeZ); end
    if ~isempty(frameIntervalSec), fprintf(', frameInterval=%.4gs (%.3gfps)', frameIntervalSec, 1/frameIntervalSec); end
    fprintf('\n');
end

meta = struct('pxSizeXY', pxSizeXY, 'pxSizeZ', pxSizeZ, 'frameIntervalSec', frameIntervalSec, ...
    'nSlices', sizeZ, 'nFrames', sizeT);

for ch = 1:sizeC
    if sizeC > 1
        chFile = sprintf('%s_C%d.tif', outFileBase, ch);
    else
        chFile = sprintf('%s.tif', outFileBase);
    end
    if isfile(chFile)
        delete(chFile);
    end

    % One Tiff handle stays open for every page of this channel - opening
    % a fresh handle per frame (the original approach) is the dominant
    % cost on a multi-thousand-frame recording and made this orders of
    % magnitude slower than it needs to be.
    tiffObj = Tiff(chFile, 'w');
    tiffCleanup = onCleanup(@() closeTiffSafely(tiffObj)); %#ok<NASGU>
    firstPage = true;
    for t = 1:sizeT
        for z = 1:sizeZ
            plane = readPlaneWithRetry(r, z, ch, t);
            if ~(isa(plane,'uint8') || isa(plane,'uint16') || isa(plane,'single'))
                plane = uint16(plane);
            end
            if ~firstPage
                tiffObj.writeDirectory();
            end
            tiffObj.setTag(imagejTagStruct(plane, meta));
            tiffObj.write(plane);
            firstPage = false;
        end
    end
    tiffObj.close();
    if opts.Verbose
        fprintf('[exportLifSeries]   wrote %s (%d pages)\n', chFile, sizeT*sizeZ);
    end
end

end


function closeTiffSafely(tiffObj)
% Best-effort close, used as onCleanup so a transient read error partway
% through a long recording still leaves the file handle released rather
% than locked, instead of erroring out of an already-erroring cleanup.
try
    tiffObj.close();
catch
end
end
