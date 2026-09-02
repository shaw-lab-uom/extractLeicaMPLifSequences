function writeSpiralPNG(result, filePath, pxSizeXY)
% =========================================
% Script: writeSpiralPNG.m
% Created: 2026-08-26
% Purpose: Writes a stitched tile-scan mosaic as an 8-bit, contrast-
%          stretched PNG instead of a calibrated 16-bit TIFF.
%
%          A spiral/tile-scan overview mosaic is dim by nature (real
%          signal sits near the bottom of the 16-bit range) and is used
%          for visual reference (finding vessels, checking window
%          quality), not quantitative fluorescence measurement - unlike
%          a plain 16-bit TIFF, which most viewers display using the
%          raw 0-65535 range and so opens looking almost entirely black
%          until you manually adjust contrast. A percentile-based
%          stretch is baked into the pixel values here so the file
%          "just looks right" in any standard image viewer straight
%          away. Pixel size is still embedded (PNG pHYs chunk) for
%          reference, though once stretched this is a display image,
%          not a calibrated one.
%
% Inputs:  result    - 2D numeric array (the stitched canvas, any class)
%          filePath  - output PNG path
%          pxSizeXY  - XY pixel size in microns (optional; omit/empty to
%                      skip embedding resolution)
% Last modified: 2026-08-26 - initial version
% =========================================

stretched = imadjust(result, stretchlim(result, [0.01 0.999]));
img8 = im2uint8(stretched);

if nargin >= 3 && ~isempty(pxSizeXY) && pxSizeXY > 0
    pxPerMeter = round(1e6 / pxSizeXY);
    imwrite(img8, filePath, 'ResolutionUnit', 'meter', ...
        'XResolution', pxPerMeter, 'YResolution', pxPerMeter);
else
    imwrite(img8, filePath);
end

end
