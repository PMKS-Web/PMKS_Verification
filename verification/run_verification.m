function summaries = run_verification(outputRoot)
%RUN_VERIFICATION Regenerate and validate the supported verification cases.
%
% The runner copies only MATLAB source into an empty scratch directory. It
% never reads committed Mechanism.mat files or prior CSV output.

verificationDirectory = fileparts(mfilename('fullpath'));
repoRoot = fileparts(verificationDirectory);
if nargin < 1 || isempty(outputRoot)
    outputRoot = fullfile(repoRoot, 'artifacts', 'matlab');
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
    'slider_crank_tracer'};

summaries = repmat(struct(), 1, numel(caseNames));
for i = 1:numel(caseNames)
    fprintf('Running %s...\n', caseNames{i});
    summaries(i) = runOneCase(caseNames{i}, repoRoot, outputRoot);
    fprintf('  PASS: %d rows, %d CSV files\n', summaries(i).rows, summaries(i).csvFiles);
end

manifest = struct();
manifest.schemaVersion = 1;
manifest.sourceRepository = 'https://github.com/PMKS-Web/PMKS_Verification';
manifest.sourceCommit = gitCommit(repoRoot);
manifest.matlabVersion = version;
manifest.matlabRelease = version('-release');
manifest.generatedAtUtc = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
manifest.cases = summaries;
writeJson(fullfile(outputRoot, 'manifest.json'), manifest);

fprintf('All %d verification cases passed.\n', numel(caseNames));
end

function summary = runOneCase(caseName, repoRoot, outputRoot)
config = verification_case_definition(caseName, repoRoot);
caseOutput = fullfile(outputRoot, caseName);
mkdir(caseOutput);

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

summary = validate_verification_case(Mechanism, config);
GeneralUtils.exportMatricesToCSV('Kin', 'CSVOutput');
if config.hasDynamics
    GeneralUtils.exportMatricesToCSV('Force', 'CSVOutput');
end

csvSource = fullfile(scratchDirectory, 'CSVOutput');
if ~isfolder(csvSource)
    error('Verification:MissingCsvOutput', '%s did not create CSV output.', caseName);
end
copyfile(csvSource, fullfile(caseOutput, 'CSVOutput'));
save(fullfile(caseOutput, 'Mechanism.mat'), 'Mechanism', '-v7');

summary.csvFiles = validateCsvTree(fullfile(caseOutput, 'CSVOutput'), summary.rows, caseName);
summary.dynamicsScope = dynamicsScope(config);

clear cleanup;
end

function count = validateCsvTree(csvRoot, rowCount, caseName)
files = dir(fullfile(csvRoot, '**', '*.csv'));
if isempty(files)
    error('Verification:NoCsvFiles', '%s produced no CSV files.', caseName);
end

for i = 1:numel(files)
    filePath = fullfile(files(i).folder, files(i).name);
    data = readmatrix(filePath);
    if ~isnumeric(data) || ~isequal(size(data), [rowCount, 3])
        error('Verification:CsvShape', '%s must contain %d rows and 3 columns.', filePath, rowCount);
    end
    if any(~isfinite(data(:)))
        error('Verification:CsvNonFinite', '%s contains non-finite values.', filePath);
    end
end
count = numel(files);
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
