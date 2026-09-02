function geom = getTileGeometry(r, omeMeta, seriesIdx, tileAnchor, swapXY)
% =========================================
% Script: getTileGeometry.m
% Created: 2026-08-26
% Purpose: Reads per-tile size/pixel-size/stage-position metadata for a
%          set of series and derives each tile's physical bounding box,
%          shared by stitchTileGroup and the orientation pre-detection
%          step so that logic isn't duplicated.
% Inputs:
%   r          - open Bio-Formats reader
%   omeMeta    - r.getMetadataStore()
%   seriesIdx  - 0-based series indices (row/col vector)
%   tileAnchor - 'center' (stage position = tile centre) or 'corner'
%                (stage position = tile top-left corner)
%   swapXY     - logical (default false): use the OME PlanePositionY
%                value as the tile's true X position and vice versa.
%                This is a documented Bio-Formats LIF quirk (the X/Y
%                stage fields can come out mislabelled for some LIF tile
%                series - see github.com/ome/bioformats/issues/3836 and
%                github.com/fiji/Stitching/issues/57) - separate from,
%                and independent of, any pixel-content flip
%                (detectTileOrientation.m/stitchTileGroup.m). Tile pixel
%                dimensions (szX/szY, pxX/pxY) are NOT swapped - only
%                which raw position value is treated as X vs Y.
% Outputs:
%   geom - struct with fields (all same order as seriesIdx):
%     szX, szY, szZ, szT, nCh, pxX, pxY  - raw per-tile metadata
%     left_um, top_um, right_um, bottom_um - physical bounding box (um)
%     outPxSize - the modal (most common) pxX in the set, used as the
%                 common resampling target (um/px) so a rare outlier
%                 tile doesn't dictate the whole mosaic's resolution
% Last modified: 2026-08-26 - added swapXY to correct a documented
%                Bio-Formats LIF stage-position mislabelling quirk
% =========================================

if nargin < 5, swapXY = false; end

seriesIdx = seriesIdx(:)';
nTiles = numel(seriesIdx);

posX = nan(nTiles,1); posY = nan(nTiles,1);
pxX  = nan(nTiles,1); pxY  = nan(nTiles,1);
szX  = nan(nTiles,1); szY  = nan(nTiles,1);
szZ  = nan(nTiles,1); szT  = nan(nTiles,1);
nCh  = nan(nTiles,1);

for i = 1:nTiles
    s = seriesIdx(i);
    r.setSeries(s);
    szX(i) = r.getSizeX(); szY(i) = r.getSizeY();
    szZ(i) = r.getSizeZ(); szT(i) = r.getSizeT();
    nCh(i) = r.getSizeC();
    pxX(i) = double(omeMeta.getPixelsPhysicalSizeX(s).value().doubleValue());
    pxY(i) = double(omeMeta.getPixelsPhysicalSizeY(s).value().doubleValue());
    posX(i) = double(omeMeta.getPlanePositionX(s,0).value().doubleValue()) * 1e6;
    posY(i) = double(omeMeta.getPlanePositionY(s,0).value().doubleValue()) * 1e6;
end

tileW_um = szX .* pxX;
tileH_um = szY .* pxY;

if swapXY
    [posX, posY] = deal(posY, posX);
end

if strcmp(tileAnchor, 'center')
    left_um = posX - tileW_um/2;
    top_um  = posY - tileH_um/2;
else
    left_um = posX;
    top_um  = posY;
end

geom.szX = szX; geom.szY = szY; geom.szZ = szZ; geom.szT = szT; geom.nCh = nCh;
geom.pxX = pxX; geom.pxY = pxY;
geom.left_um = left_um; geom.top_um = top_um;
geom.right_um = left_um + tileW_um;
geom.bottom_um = top_um + tileH_um;
% Use the mosaic's most common tile pixel size as the output resolution -
% not the finest one present. A single stray high-res tile (e.g. a manual
% zoom-in/focus-check snapshot LAS X saved mid-scan) would otherwise force
% every other tile in the mosaic to be massively upsampled to match it.
geom.outPxSize = mode(round(pxX, 3));

end
