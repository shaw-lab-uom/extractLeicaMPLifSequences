function writeImageJTiff(plane, filePath, meta)
% =========================================
% Script: writeImageJTiff.m
% Created: 2026-08-26
% Purpose: Writes a single-page TIFF with calibration metadata in the
%          ImageJ convention (ResolutionUnit=None, XY resolution =
%          pixels-per-micron, ImageDescription unit=micron) - the format
%          ImageJ/Fiji reads natively to recover pixel size without any
%          manual recalibration. For multi-page output (Z-stacks, time
%          series), see exportLifSeries.m, which keeps one Tiff handle
%          open across all pages instead of reopening the file per page.
%
% Inputs:
%   plane    - 2D numeric array (uint8/uint16/single)
%   filePath - output TIFF path (overwritten if it already exists)
%   meta     - struct, see imagejTagStruct.m: pxSizeXY (required for
%              spatial calibration; omit/empty to skip it)
% Last modified: 2026-08-26 - simplified to single-page only (append
%                mode moved into exportLifSeries.m for speed - reopening
%                a Tiff object per frame was the bottleneck on
%                multi-thousand-frame recordings)
% =========================================

if nargin < 3, meta = struct(); end
if ~(isa(plane,'uint8') || isa(plane,'uint16') || isa(plane,'single'))
    plane = uint16(plane);
end

if isfile(filePath)
    delete(filePath);
end

t = Tiff(filePath, 'w');
t.setTag(imagejTagStruct(plane, meta));
t.write(plane);
t.close();

end
