function flat = estimateFlatField(planes)
% =========================================
% Script: estimateFlatField.m
% Created: 2026-08-26
% Purpose: Estimates a smooth per-pixel illumination/gain field from an
%          ensemble of same-sized tiles, using their median projection
%          (robust to real bright structures like vessels, since those
%          don't sit in the same pixel across many different tiles)
%          smoothed with a wide Gaussian to keep only the low-frequency
%          illumination trend. Used to correct the per-tile brightness
%          checkerboard that live-scan gain/exposure changes leave in
%          an unmerged tile scan, when no separate calibration/blank
%          image is available.
% Inputs:  planes - cell array of 2D numeric arrays, ALL THE SAME SIZE
% Outputs: flat   - 2D single array, same size, mean(flat(:)) == 1, so
%                   dividing a tile by this field corrects relative
%                   brightness without changing its overall intensity scale
% Last modified: 2026-08-26 - initial version
% =========================================

if ~iscell(planes) || isempty(planes)
    error('estimateFlatField:invalidInput', 'planes must be a non-empty cell array.');
end

sz = size(planes{1});
stack = zeros([sz, numel(planes)], 'single');
for i = 1:numel(planes)
    if ~isequal(size(planes{i}), sz)
        error('estimateFlatField:sizeMismatch', 'All planes must be the same size.');
    end
    stack(:,:,i) = single(planes{i});
end

med = median(stack, 3);
sigma = max(sz)/6;
flat = imgaussfilt(med, sigma);
flat = flat / mean(flat(:), 'omitnan');
flat(flat <= 0 | isnan(flat)) = 1;   % guard against degenerate values

end
