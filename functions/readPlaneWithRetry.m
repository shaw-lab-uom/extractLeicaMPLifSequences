function plane = readPlaneWithRetry(r, z, ch, t)
% =========================================
% Script: readPlaneWithRetry.m
% Created: 2026-08-26
% Purpose: Wraps bfGetPlaneAtZCT with a few retries and a short pause,
%          since reading a multi-GB .lif over network storage (e.g. a
%          mapped drive) can hit a transient I/O error partway through a
%          long export (thousands of frames) that succeeds if retried a
%          moment later - without this, one network blip kills the whole
%          export run.
% Inputs:  r - open Bio-Formats reader; z,ch,t - 1-based plane indices
% Outputs: plane - the plane, as returned by bfGetPlaneAtZCT
% Last modified: 2026-08-26 - initial version
% =========================================

maxAttempts = 4;
lastErr = [];
for attempt = 1:maxAttempts
    try
        plane = bfGetPlaneAtZCT(r, z, ch, t);
        return
    catch ME
        lastErr = ME;
        if attempt < maxAttempts
            pause(2 * attempt);
        end
    end
end
error('readPlaneWithRetry:failed', ...
    'Failed to read plane (z=%d,c=%d,t=%d) after %d attempts: %s', ...
    z, ch, t, maxAttempts, lastErr.message);

end
