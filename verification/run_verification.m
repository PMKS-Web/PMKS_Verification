function summaries = run_verification(outputRoot, selectedCases)
%RUN_VERIFICATION Regenerate and validate MATLAB source tables for v1.
%
% The runner copies only MATLAB source into an empty scratch directory. It
% never reads committed Mechanism.mat files or prior CSV output.
%
% RUN_VERIFICATION(OUTPUTROOT) runs every case, which is what a local
% regeneration wants.
%
% RUN_VERIFICATION(OUTPUTROOT, SELECTEDCASES) runs only the named cases so CI can
% shard them across runners. Cases are already independent -- each gets its own
% scratch directory and clears the previous case's functions before running -- so
% a subset produces byte-identical output for the cases it covers. Its run report
% then describes only that subset, and the shards are merged downstream.

verificationDirectory = fileparts(mfilename('fullpath'));
repoRoot = fileparts(verificationDirectory);
if nargin < 1 || isempty(outputRoot)
    outputRoot = fullfile(repoRoot, 'artifacts', 'candidate', 'reference-data', 'v1');
end
outputRoot = char(outputRoot);

if isfolder(outputRoot)
    rmdir(outputRoot, 's');
end
mkdir(outputRoot);

caseNames = {
    'watt_i', ...
    'stephenson_iii_example_2', ...
    'teaching_four_bar', ...
    'teaching_slider_crank', ...
    'slider_crank_tracer', ...
    'steep_slider_crank'};

if nargin >= 2 && ~isempty(selectedCases)
    if ischar(selectedCases) || isstring(selectedCases)
        selectedCases = cellstr(selectedCases);
    end
    selectedCases = cellfun(@char, selectedCases, 'UniformOutput', false);
    unknown = setdiff(selectedCases, caseNames);
    if ~isempty(unknown)
        error('Verification:UnknownCase', ...
            'Unknown verification case(s): %s', strjoin(unknown, ', '));
    end
    % Filter rather than reorder, so a shard's output cannot depend on the order
    % its names happened to be passed in.
    caseNames = caseNames(ismember(caseNames, selectedCases));
end

summaries = struct([]);
for i = 1:numel(caseNames)
    fprintf('Running %s...\n', caseNames{i});
    summary = runOneCase(caseNames{i}, repoRoot, outputRoot);
    if isempty(summaries)
        summaries = summary;
    else
        summaries(end + 1) = summary; %#ok<AGROW>
    end
    fprintf('  PASS: %d rows, %d CSV files\n', summary.rows, summary.files);
end

runReport = struct();
runReport.schemaVersion = 1;
runReport.sourceRepository = 'https://github.com/PMKS-Web/PMKS_Verification';
runReport.sourceCommit = gitCommit(repoRoot);
runReport.matlabVersion = version;
runReport.matlabRelease = version('-release');
products = ver;
runReport.matlabProducts = rmfield(products, {'Date'});
runReport.generatedAtUtc = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
runReport.cases = summaries;
writeJson(fullfile(fileparts(outputRoot), 'run-report.json'), runReport);

fprintf('All %d verification cases passed: %s\n', numel(caseNames), strjoin(caseNames, ', '));
end

function summary = runOneCase(caseName, repoRoot, outputRoot)
config = verification_case_definition(caseName, repoRoot);
caseOutput = fullfile(outputRoot, 'cases', caseName);
mkdir(caseOutput);
copyfile(fullfile(repoRoot, 'reference-data', 'v1', 'cases', caseName, 'case.json'), ...
    fullfile(caseOutput, 'case.json'));

scratchDirectory = tempname;
mkdir(scratchDirectory);
copyfile(fullfile(config.sourceDirectory, '*.m'), scratchDirectory);

originalDirectory = pwd;
originalPath = path;
cleanup = onCleanup(@() cleanupEnvironment(originalDirectory, originalPath, scratchDirectory));
cd(scratchDirectory);
addpath(scratchDirectory, '-begin');
addpath(fullfile(repoRoot, 'CommonUtils'), '-end');
clearCaseFunctions();
rehash;

solverPath = which('PosSolver');
if ~startsWith(solverPath, scratchDirectory)
    error('Verification:WrongSolver', 'Resolved PosSolver to %s instead of %s.', solverPath, scratchDirectory);
end

Mechanism = build_verification_case(caseName, config);
Mechanism = PosSolver(Mechanism, config.inputSpeed);
Mechanism = VelAccSolver(Mechanism);
if config.hasDynamics
    Mechanism = ForceSolver(Mechanism, config.scenarios);
end

metrics = validate_verification_case(Mechanism, config);
exported = export_reference_v1(Mechanism, config, caseOutput, repoRoot);
summary = exported;
summary.speedRpm = config.speedRpm;
summary.hasDynamics = config.hasDynamics;
summary.maxLengthDrift = metrics.maxLengthDrift;
summary.maxVelocityConstraintResidual = metrics.maxVelocityConstraintResidual;
summary.maxAccelerationConstraintResidual = metrics.maxAccelerationConstraintResidual;
summary.dynamicsScope = dynamicsScope(config);

clear cleanup;
end

function value = dynamicsScope(config)
if config.hasDynamics
    value = 'Newton-Euler, gravity on and off, friction disabled';
else
    value = 'kinematics only';
end
end

function commit = gitCommit(repoRoot)
[status, output] = system(sprintf('git -C "%s" rev-parse HEAD', repoRoot));
if status ~= 0
    error('Verification:GitCommit', 'Could not determine the source commit.');
end
commit = strtrim(output);
end

function writeJson(filePath, value)
fileId = fopen(filePath, 'w');
if fileId == -1
    error('Verification:ManifestWrite', 'Could not open %s for writing.', filePath);
end
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, jsonencode(value, 'PrettyPrint', true), 'char');
fwrite(fileId, newline, 'char');
clear cleanup;
end

function clearCaseFunctions()
clear('PosSolver', 'VelAccSolver', 'ForceSolver', 'StressSolver', 'Utils');
end

function cleanupEnvironment(originalDirectory, originalPath, scratchDirectory)
cd(originalDirectory);
path(originalPath);
clearCaseFunctions();
if isfolder(scratchDirectory)
    rmdir(scratchDirectory, 's');
end
end
