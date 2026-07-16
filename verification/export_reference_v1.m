function summary = export_reference_v1(Mechanism, config, caseOutput, repoRoot)
%EXPORT_REFERENCE_V1 Serialize one MATLAB result into the normative v1 layout.

manifestPath = fullfile(repoRoot, 'reference-data', 'v1', 'cases', config.name, 'case.json');
manifest = jsondecode(fileread(manifestPath));
rejectLegacyPath(caseOutput);

matlabRoot = fullfile(caseOutput, 'matlab');
makeCleanDirectory(matlabRoot);
mkdir(fullfile(matlabRoot, 'joints'));
mkdir(fullfile(matlabRoot, 'points'));
mkdir(fullfile(matlabRoot, 'com'));
mkdir(fullfile(matlabRoot, 'links'));

[sampleIds, sweepIds, sweepIndices, inputAngles, directions, times, conditions, eligibility] = ...
    buildSamples(Mechanism, manifest, config);
sampleRows = cell(numel(sampleIds), 8);
for i = 1:numel(sampleIds)
    sampleRows(i, :) = {sampleIds{i}, sweepIds{i}, sweepIndices(i), inputAngles(i), ...
        directions(i), times(i), conditions(i), eligibility{i}};
end
writeCsv(fullfile(matlabRoot, 'samples.csv'), ...
    {'sample_id', 'sweep_id', 'sweep_index', 'input_angle_rad', 'input_direction', ...
    'time_s', 'jacobian_condition', 'eligibility'}, sampleRows);

jointSpecs = manifest.topology.joints;
for i = 1:numel(jointSpecs)
    jointId = jointSpecs(i).id;
    writePointSeries(fullfile(matlabRoot, 'joints', [jointId '.csv']), sampleIds, ...
        Mechanism.Joint.(jointId), speedValue(Mechanism.LinVel.Joint.(jointId), config.speedField), ...
        speedValue(Mechanism.LinAcc.Joint.(jointId), config.speedField));
end

pointSpecs = manifest.topology.points;
for i = 1:numel(pointSpecs)
    pointId = pointSpecs(i).id;
    writePointSeries(fullfile(matlabRoot, 'points', [pointId '.csv']), sampleIds, ...
        Mechanism.TracerPoint.(pointId), speedValue(Mechanism.LinVel.Joint.(pointId), config.speedField), ...
        speedValue(Mechanism.LinAcc.Joint.(pointId), config.speedField));
end

comNames = fieldnames(Mechanism.LinkCoM);
for i = 1:numel(comNames)
    linkId = comNames{i};
    writePointSeries(fullfile(matlabRoot, 'com', [linkId '.csv']), sampleIds, ...
        Mechanism.LinkCoM.(linkId), speedValue(Mechanism.LinVel.LinkCoM.(linkId), config.speedField), ...
        speedValue(Mechanism.LinAcc.LinkCoM.(linkId), config.speedField));
end

linkSpecs = manifest.topology.links;
for i = 1:numel(linkSpecs)
    linkId = linkSpecs(i).id;
    basis = linkSpecs(i).angle_basis;
    firstPosition = namedPosition(Mechanism, basis{1});
    secondPosition = namedPosition(Mechanism, basis{2});
    theta = unwrap(atan2(secondPosition(:, 2) - firstPosition(:, 2), ...
        secondPosition(:, 1) - firstPosition(:, 1)));
    theta = theta - theta(1);
    omega = speedValue(Mechanism.AngVel.(linkId), config.speedField);
    alpha = speedValue(Mechanism.AngAcc.(linkId), config.speedField);
    rows = cell(numel(sampleIds), 4);
    for row = 1:numel(sampleIds)
        rows(row, :) = {sampleIds{row}, theta(row), omega(row, 3), alpha(row, 3)};
    end
    writeCsv(fullfile(matlabRoot, 'links', [linkId '.csv']), ...
        {'sample_id', 'theta_delta_rad', 'omega_rad_s', 'alpha_rad_s2'}, rows);
end

if config.hasDynamics
    exportDynamics(Mechanism, config, matlabRoot, sampleIds);
end

summary = struct();
summary.name = config.name;
summary.rows = numel(sampleIds);
summary.sweeps = numel(unique(sweepIds));
summary.singularRows = sum(strcmp(eligibility, 'singular'));
summary.files = numel(dir(fullfile(matlabRoot, '**', '*.csv')));
end

function [sampleIds, sweepIds, sweepIndices, angles, directions, times, conditions, eligibility] = ...
    buildSamples(Mechanism, manifest, config)
rowCount = size(Mechanism.Joint.A, 1);
expectedSweeps = manifest.input.expected_sweeps;
expectedRows = 0;
for sweepIndex = 1:numel(expectedSweeps)
    expectedSweep = jsonStruct(expectedSweeps, sweepIndex);
    expectedRows = expectedRows + expectedSweep.rows;
end
if expectedRows ~= rowCount
    error('Verification:SweepRows', '%s produced %d rows; manifest expects %d.', ...
        config.name, rowCount, expectedRows);
end

rawAngles = atan2(Mechanism.Joint.B(:, 2) - Mechanism.Joint.A(:, 2), ...
    Mechanism.Joint.B(:, 1) - Mechanism.Joint.A(:, 1));
sampleIds = cell(rowCount, 1);
sweepIds = cell(rowCount, 1);
sweepIndices = zeros(rowCount, 1);
angles = zeros(rowCount, 1);
directions = zeros(rowCount, 1);
conditions = zeros(rowCount, 1);
eligibility = cell(rowCount, 1);
times = (0:(rowCount - 1))' * manifest.input.angle_increment_rad / abs(manifest.input.speed_rad_s);

firstRow = 1;
for sweepIndex = 1:numel(expectedSweeps)
    expectedSweep = jsonStruct(expectedSweeps, sweepIndex);
    lastRow = firstRow + expectedSweep.rows - 1;
    rows = firstRow:lastRow;
    sweepAngle = unwrap(rawAngles(rows));
    direction = expectedSweep.direction;
    if numel(rows) > 1
        deltas = diff(sweepAngle);
        if any(direction * deltas < -1e-10)
            error('Verification:SweepDirection', '%s sweep %d contradicts its declared direction.', ...
                config.name, sweepIndex - 1);
        end
    end
    for localIndex = 1:numel(rows)
        row = rows(localIndex);
        sampleIds{row} = sprintf('matlab_%04d', row - 1);
        sweepIds{row} = sprintf('matlab_sweep_%02d', sweepIndex - 1);
        sweepIndices(row) = localIndex - 1;
        angles(row) = sweepAngle(localIndex);
        directions(row) = direction;
    end
    firstRow = lastRow + 1;
end

for row = 1:rowCount
    conditions(row) = jacobianCondition(Mechanism, manifest, row);
    if conditions(row) > manifest.jacobian.singular_condition_threshold
        eligibility{row} = 'singular';
    else
        eligibility{row} = 'eligible';
    end
end
end

function value = jsonStruct(values, index)
% JSONDECODE returns a cell array when sibling objects do not have identical fields.
if iscell(values)
    value = values{index};
else
    value = values(index);
end
if ~isstruct(value)
    error('Verification:JsonStruct', 'Expected JSON object at index %d.', index);
end
end

function value = jacobianCondition(Mechanism, manifest, row)
unknowns = manifest.jacobian.unknown_joints;
lengthConstraints = manifest.jacobian.length_constraints;
guideConstraints = manifest.jacobian.guide_constraints;
matrix = zeros(size(lengthConstraints, 1) + numel(guideConstraints), 2 * numel(unknowns));
characteristicLength = manifest.characteristic_length;

for constraintIndex = 1:size(lengthConstraints, 1)
    [firstId, secondId] = jsonPair(lengthConstraints, constraintIndex);
    firstAll = namedPosition(Mechanism, firstId);
    secondAll = namedPosition(Mechanism, secondId);
    delta = firstAll(row, 1:2) - secondAll(row, 1:2);
    initialLength = norm(firstAll(1, 1:2) - secondAll(1, 1:2));
    derivative = delta * characteristicLength / (initialLength ^ 2);
    firstUnknown = find(strcmp(unknowns, firstId), 1);
    secondUnknown = find(strcmp(unknowns, secondId), 1);
    if ~isempty(firstUnknown)
        matrix(constraintIndex, (2 * firstUnknown - 1):(2 * firstUnknown)) = derivative;
    end
    if ~isempty(secondUnknown)
        matrix(constraintIndex, (2 * secondUnknown - 1):(2 * secondUnknown)) = -derivative;
    end
end

for guideIndex = 1:numel(guideConstraints)
    spec = guideConstraints(guideIndex);
    unknownIndex = find(strcmp(unknowns, spec.joint), 1);
    if isempty(unknownIndex)
        error('Verification:GuideUnknown', 'Guide joint %s is not a Jacobian unknown.', spec.joint);
    end
    axis = spec.axis / norm(spec.axis);
    normal = [-axis(2), axis(1)];
    matrix(size(lengthConstraints, 1) + guideIndex, ...
        (2 * unknownIndex - 1):(2 * unknownIndex)) = normal;
end

singularValues = svd(matrix);
if isempty(singularValues) || singularValues(end) == 0
    value = 1e300;
else
    value = singularValues(1) / singularValues(end);
    if ~isfinite(value), value = 1e300; end
end
end

function [firstValue, secondValue] = jsonPair(values, index)
% JSONDECODE represents an array of string pairs as a column of cell arrays.
% Also accept an N-by-2 cell array for compatibility with older MATLAB releases.
if size(values, 2) >= 2
    firstValue = values{index, 1};
    secondValue = values{index, 2};
    return;
end
pair = values{index};
if ~iscell(pair) || numel(pair) ~= 2
    error('Verification:JsonPair', 'Expected JSON string pair at index %d.', index);
end
firstValue = pair{1};
secondValue = pair{2};
end

function exportDynamics(Mechanism, config, matlabRoot, sampleIds)
scenarios = {
    'newton_no_gravity', 'NoGrav';
    'newton_gravity', 'Grav'};
for scenarioIndex = 1:size(scenarios, 1)
    scenarioId = scenarios{scenarioIndex, 1};
    gravityField = scenarios{scenarioIndex, 2};
    result = Mechanism.ForceAnalysis.Newton.(gravityField).NoFriction.(config.speedField);
    scenarioRoot = fullfile(matlabRoot, 'dynamics', scenarioId);
    mkdir(fullfile(scenarioRoot, 'joints'));
    jointNames = fieldnames(result.Joint);
    for jointIndex = 1:numel(jointNames)
        jointId = jointNames{jointIndex};
        values = result.Joint.(jointId);
        rows = cell(numel(sampleIds), 3);
        for row = 1:numel(sampleIds)
            rows(row, :) = {sampleIds{row}, values(row, 1), values(row, 2)};
        end
        writeCsv(fullfile(scenarioRoot, 'joints', [jointId '.csv']), ...
            {'sample_id', 'fx', 'fy'}, rows);
    end
    torqueRows = cell(numel(sampleIds), 2);
    for row = 1:numel(sampleIds)
        torqueRows(row, :) = {sampleIds{row}, result.Torque(row, 3)};
    end
    writeCsv(fullfile(scenarioRoot, 'input_torque.csv'), {'sample_id', 'torque_nm'}, torqueRows);
end
end

function writePointSeries(filePath, sampleIds, position, velocity, acceleration)
rows = cell(numel(sampleIds), 7);
for row = 1:numel(sampleIds)
    rows(row, :) = {sampleIds{row}, position(row, 1), position(row, 2), ...
        velocity(row, 1), velocity(row, 2), acceleration(row, 1), acceleration(row, 2)};
end
writeCsv(filePath, {'sample_id', 'x', 'y', 'vx', 'vy', 'ax', 'ay'}, rows);
end

function value = speedValue(value, speedField)
if isstruct(value)
    value = value.(speedField);
end
end

function value = namedPosition(Mechanism, pointId)
if isfield(Mechanism.Joint, pointId)
    value = Mechanism.Joint.(pointId);
elseif isfield(Mechanism.TracerPoint, pointId)
    value = Mechanism.TracerPoint.(pointId);
else
    error('Verification:UnknownPoint', 'Unknown point %s.', pointId);
end
end

function writeCsv(filePath, header, rows)
parent = fileparts(filePath);
if ~isfolder(parent), mkdir(parent); end
fileId = fopen(filePath, 'w');
if fileId == -1, error('Verification:CsvWrite', 'Cannot write %s.', filePath); end
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, '%s\n', strjoin(header, ','));
for row = 1:size(rows, 1)
    fields = cell(1, size(rows, 2));
    for column = 1:size(rows, 2)
        value = rows{row, column};
        if isnumeric(value)
            fields{column} = sprintf('%.17g', value);
        else
            fields{column} = char(value);
        end
    end
    fprintf(fileId, '%s\n', strjoin(fields, ','));
end
clear cleanup;
end

function makeCleanDirectory(directory)
if isfolder(directory), rmdir(directory, 's'); end
mkdir(directory);
end

function rejectLegacyPath(directory)
normalized = strrep(char(directory), '\\', '/');
if contains(normalized, '/legacy/') || contains(normalized, '/CSVOutput')
    error('Verification:LegacyPath', 'v1 generators reject legacy output path %s.', directory);
end
end
