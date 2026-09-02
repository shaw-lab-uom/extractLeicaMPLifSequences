% =========================================
% Script: extractLeicaMPLifSequences.m
% Created: 2026-08-26
% Purpose: Extracts every distinct scan inside a Leica .lif file to
%          plain, calibrated TIFFs, written into the same folder as the
%          .lif - so nobody needs to open the .lif in LAS X/ImageJ just
%          to get images out of it:
%            - Unmerged tile-scan mosaics (e.g. a Navigator spiral saved
%              without ticking "merge") are stitched into one image
%              using each tile's stage-position metadata. Tile
%              orientation and a documented Bio-Formats stage-position
%              quirk are corrected automatically by testing the real
%              tile overlaps, not assumed - see functions\lifToTiffs.m
%              for the full pipeline description.
%            - Z-stacks and time series are saved as multi-page TIFFs.
%            - Multi-channel data is split into one TIFF per channel.
%            - Pixel size, Z-step, and frame interval are embedded using
%              ImageJ's own TIFF convention, so they read back
%              calibrated automatically.
%
% HOW TO USE (for collaborators):
%   1. One-time setup: install the Bio-Formats MATLAB toolbox (bfmatlab)
%      from https://www.openmicroscopy.org/bio-formats/downloads/ (the
%      "bfmatlab.zip" under the latest version's "artifacts" folder),
%      unzip it anywhere, and add that folder to your MATLAB path
%      (Home tab > Set Path > Add Folder... > OK > Save), or just place
%      the unzipped bfmatlab folder inside your Documents\MATLAB, which
%      is on the path automatically.
%   2. Edit EXP_DIR below to point at the folder containing your .lif
%      file(s).
%   3. Run this script. Every .lif file found directly in EXP_DIR is
%      processed in turn; outputs are written alongside each .lif,
%      named "<lifFileName>_<scanName>_<YYYYMMDD>[_C#].tif".
%
% Inputs:  EXP_DIR (edit the line below) - folder containing one or more
%          .lif files
% Outputs: calibrated TIFFs written into EXP_DIR (see functions\lifToTiffs.m
%          for exactly how each scan type is handled)
% Last modified: 2026-08-26 - initial version
% =========================================

%% ===== USER SETTINGS - edit this line, then run the script (F5) =====
EXP_DIR = 'Z:\RawDataStore\TwoPhoton\ecGCaMP_imaging\25082026';
%% ======================================================================

% Make the helper functions available regardless of where this folder
% has been placed/copied to.
thisFileDir = fileparts(mfilename('fullpath'));
addpath(fullfile(thisFileDir, 'functions'));

if isempty(which('bfGetReader'))
    error('extractLeicaMPLifSequences:bioformatsMissing', ['%s\n%s\n%s\n%s'], ...
        'Bio-Formats MATLAB toolbox (bfmatlab) not found on your MATLAB path.', ...
        'Download it from https://www.openmicroscopy.org/bio-formats/downloads/', ...
        '(bfmatlab.zip, under the latest version''s "artifacts"), unzip it, and', ...
        'add that folder to your MATLAB path (Set Path > Add Folder), then re-run this script.');
end

if ~isfolder(EXP_DIR)
    error('extractLeicaMPLifSequences:badExpDir', 'EXP_DIR does not exist: %s', EXP_DIR);
end

lifFiles = dir(fullfile(EXP_DIR, '*.lif'));
if isempty(lifFiles)
    error('extractLeicaMPLifSequences:noLifFiles', 'No .lif files found in EXP_DIR: %s', EXP_DIR);
end

fprintf('Found %d .lif file(s) in %s\n', numel(lifFiles), EXP_DIR);
for i = 1:numel(lifFiles)
    fprintf('\n============================================================\n');
    fprintf('Processing %s (%d/%d)\n', lifFiles(i).name, i, numel(lifFiles));
    fprintf('============================================================\n');
    lifToTiffs(EXP_DIR, lifFiles(i).name);
end

fprintf('\nAll done. Outputs are in %s\n', EXP_DIR);
