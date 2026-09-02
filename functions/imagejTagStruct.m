function tagstruct = imagejTagStruct(plane, meta)
% =========================================
% Script: imagejTagStruct.m
% Created: 2026-08-26
% Purpose: Builds the Tiff tag struct (including an ImageJ-hyperstack
%          ImageDescription block) for one calibrated page - shared by
%          writeImageJTiff.m (single-page) and exportLifSeries.m
%          (multi-page, which sets these tags once per page on an
%          already-open Tiff object for speed).
% Inputs:
%   plane - 2D numeric array (uint8/uint16/single) for this page
%   meta  - struct: pxSizeXY (um, spatial calib), pxSizeZ (um, Z step),
%           frameIntervalSec (s), nSlices, nFrames - see writeImageJTiff.m
% Outputs:
%   tagstruct - struct ready for Tiff.setTag()
% Last modified: 2026-08-26 - split out of writeImageJTiff so a
%                multi-page writer can reuse it without reopening the
%                file for every page
% =========================================

tagstruct = struct();
tagstruct.ImageLength = size(plane,1);
tagstruct.ImageWidth = size(plane,2);
tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
tagstruct.SamplesPerPixel = 1;
tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
tagstruct.Compression = Tiff.Compression.None;

switch class(plane)
    case 'uint8'
        tagstruct.BitsPerSample = 8;
    case 'uint16'
        tagstruct.BitsPerSample = 16;
    case 'single'
        tagstruct.BitsPerSample = 32;
        tagstruct.SampleFormat = Tiff.SampleFormat.IEEEFP;
    otherwise
        tagstruct.BitsPerSample = 16;
end

hasXY = isfield(meta,'pxSizeXY') && ~isempty(meta.pxSizeXY) && meta.pxSizeXY > 0;
if hasXY
    tagstruct.ResolutionUnit = Tiff.ResolutionUnit.None;
    tagstruct.XResolution = 1/meta.pxSizeXY;
    tagstruct.YResolution = 1/meta.pxSizeXY;
end

nSlices = 1; if isfield(meta,'nSlices') && ~isempty(meta.nSlices), nSlices = meta.nSlices; end
nFrames = 1; if isfield(meta,'nFrames') && ~isempty(meta.nFrames), nFrames = meta.nFrames; end

descLines = {'ImageJ=1.11a'};
if nSlices > 1, descLines{end+1} = sprintf('slices=%d', nSlices); end
if nFrames > 1, descLines{end+1} = sprintf('frames=%d', nFrames); end
if nSlices > 1 && nFrames > 1, descLines{end+1} = 'hyperstack=true'; end
if hasXY, descLines{end+1} = 'unit=micron'; end
if isfield(meta,'pxSizeZ') && ~isempty(meta.pxSizeZ) && meta.pxSizeZ > 0
    descLines{end+1} = sprintf('spacing=%.6g', meta.pxSizeZ);
end
if isfield(meta,'frameIntervalSec') && ~isempty(meta.frameIntervalSec) && meta.frameIntervalSec > 0
    descLines{end+1} = sprintf('finterval=%.6g', meta.frameIntervalSec);
end
tagstruct.ImageDescription = strjoin(descLines, newline);

end
