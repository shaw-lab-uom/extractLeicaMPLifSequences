function outStr = sanitizeFileName(inStr)
% =========================================
% Script: sanitizeFileName.m
% Created: 2026-08-26
% Purpose: Replace characters that are invalid (or awkward) in Windows
%          filenames with underscores, so LAS X image/series names
%          (which often contain '/') can be used safely in output
%          filenames.
% Inputs:  inStr  - char or string
% Outputs: outStr - char, filesystem-safe version of inStr
% Last modified: 2026-08-26 - initial version
% =========================================

if ~(ischar(inStr) || isstring(inStr))
    error('sanitizeFileName:invalidInput', 'inStr must be a char or string.');
end

outStr = char(inStr);
invalidChars = '<>:"/\|?*';
for k = 1:numel(invalidChars)
    outStr(outStr == invalidChars(k)) = '_';
end
outStr = strtrim(outStr);

end
