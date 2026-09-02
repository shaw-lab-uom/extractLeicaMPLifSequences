function planesOut = applyFlatField(planesIn, verbose)
% =========================================
% Script: applyFlatField.m
% Created: 2026-08-26
% Purpose: Groups a set of tile planes by pixel shape, estimates one
%          flat field per shape via estimateFlatField, and divides each
%          plane by its matching flat field. Shape groups too small to
%          estimate their own flat field reliably (<5 tiles) borrow the
%          flat field from the largest group, resized to match.
% Inputs:  planesIn - cell array of 2D numeric arrays (any/mixed sizes)
%          verbose  - true/false, print what was done (default false)
% Outputs: planesOut - cell array, same sizes as planesIn, flat-field corrected
% Last modified: 2026-08-26 - initial version
% =========================================

if nargin < 2, verbose = false; end
if ~iscell(planesIn) || isempty(planesIn)
    error('applyFlatField:invalidInput', 'planesIn must be a non-empty cell array.');
end

nP = numel(planesIn);
shapes = zeros(nP,2);
for i = 1:nP
    shapes(i,:) = size(planesIn{i});
end
[uShapes, ~, ic] = unique(shapes, 'rows');
counts = accumarray(ic, 1);
[~, majorIdx] = max(counts);
majorFlat = estimateFlatField(planesIn(ic == majorIdx));

planesOut = planesIn;
for g = 1:size(uShapes,1)
    members = find(ic == g);
    if numel(members) >= 5
        flat = estimateFlatField(planesIn(members));
        src = 'estimated locally';
    else
        flat = imresize(majorFlat, uShapes(g,:), 'bilinear');
        src = 'borrowed from majority shape';
    end
    for m = members'
        planesOut{m} = planesIn{m} ./ flat;
    end
    if verbose
        fprintf('[applyFlatField] shape %dx%d: %d tile(s), flat field %s\n', ...
            uShapes(g,1), uShapes(g,2), numel(members), src);
    end
end

end
