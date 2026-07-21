function metrics = validate_verification_case(Mechanism, config)
%VALIDATE_VERIFICATION_CASE Check shape, finiteness, and rigid-body invariants.

rowCount = size(Mechanism.Joint.A, 1);
if rowCount < 3 || rowCount >= 900
    error('Verification:InvalidRowCount', '%s produced %d rows.', config.name, rowCount);
end

validateTrajectoryStruct(Mechanism.Joint, rowCount, [config.name '.Joint']);
validateTrajectoryStruct(Mechanism.TracerPoint, rowCount, [config.name '.TracerPoint']);
validateTrajectoryStruct(Mechanism.LinkCoM, rowCount, [config.name '.LinkCoM']);

if size(Mechanism.inputSpeed, 1) ~= rowCount || any(~isfinite(Mechanism.inputSpeed(:)))
    error('Verification:InvalidInputSpeed', '%s has invalid input-speed data.', config.name);
end

validateKinematicStruct(Mechanism.AngVel, rowCount, config.speedField, [config.name '.AngVel']);
validateKinematicStruct(Mechanism.LinVel.Joint, rowCount, config.speedField, [config.name '.LinVel.Joint']);
validateKinematicStruct(Mechanism.LinVel.LinkCoM, rowCount, config.speedField, [config.name '.LinVel.LinkCoM']);
validateKinematicStruct(Mechanism.AngAcc, rowCount, config.speedField, [config.name '.AngAcc']);
validateKinematicStruct(Mechanism.LinAcc.Joint, rowCount, config.speedField, [config.name '.LinAcc.Joint']);
validateKinematicStruct(Mechanism.LinAcc.LinkCoM, rowCount, config.speedField, [config.name '.LinAcc.LinkCoM']);

maxLengthDrift = 0;
maxVelocityResidual = 0;
maxAccelerationResidual = 0;

for i = 1:size(config.constraints, 1)
    firstName = config.constraints{i, 1};
    secondName = config.constraints{i, 2};
    firstPosition = pointPosition(Mechanism, firstName);
    secondPosition = pointPosition(Mechanism, secondName);
    relativePosition = secondPosition - firstPosition;
    lengths = sqrt(sum(relativePosition .^ 2, 2));
    lengthDrift = max(abs(lengths - lengths(1)));
    positionTolerance = 1e-8 * max(1, lengths(1));
    if lengthDrift > positionTolerance
        error('Verification:RigidLength', '%s constraint %s-%s drifted by %.12g (limit %.12g).', ...
            config.name, firstName, secondName, lengthDrift, positionTolerance);
    end

    firstVelocity = pointKinematics(Mechanism.LinVel, firstName, config.speedField);
    secondVelocity = pointKinematics(Mechanism.LinVel, secondName, config.speedField);
    relativeVelocity = secondVelocity - firstVelocity;
    velocityResidual = abs(sum(relativePosition .* relativeVelocity, 2));
    velocityScale = max(1, max(lengths) * max(sqrt(sum(relativeVelocity .^ 2, 2))));
    velocityTolerance = 1e-8 * velocityScale;
    if max(velocityResidual) > velocityTolerance
        error('Verification:RigidVelocity', '%s constraint %s-%s velocity residual %.12g exceeds %.12g.', ...
            config.name, firstName, secondName, max(velocityResidual), velocityTolerance);
    end

    firstAcceleration = pointKinematics(Mechanism.LinAcc, firstName, config.speedField);
    secondAcceleration = pointKinematics(Mechanism.LinAcc, secondName, config.speedField);
    relativeAcceleration = secondAcceleration - firstAcceleration;
    accelerationResidual = abs(sum(relativePosition .* relativeAcceleration, 2) + sum(relativeVelocity .^ 2, 2));
    accelerationScale = max(1, max(lengths) * max(sqrt(sum(relativeAcceleration .^ 2, 2))) + ...
        max(sum(relativeVelocity .^ 2, 2)));
    accelerationTolerance = 1e-7 * accelerationScale;
    if max(accelerationResidual) > accelerationTolerance
        error('Verification:RigidAcceleration', '%s constraint %s-%s acceleration residual %.12g exceeds %.12g.', ...
            config.name, firstName, secondName, max(accelerationResidual), accelerationTolerance);
    end

    maxLengthDrift = max(maxLengthDrift, lengthDrift);
    maxVelocityResidual = max(maxVelocityResidual, max(velocityResidual));
    maxAccelerationResidual = max(maxAccelerationResidual, max(accelerationResidual));
end

if config.hasDynamics
    validateDynamics(Mechanism, config, rowCount);
end

validateRegressionGates(Mechanism, config);

metrics = struct();
metrics.name = config.name;
metrics.rows = rowCount;
metrics.speedRpm = config.speedRpm;
metrics.hasDynamics = config.hasDynamics;
metrics.maxLengthDrift = maxLengthDrift;
metrics.maxVelocityConstraintResidual = maxVelocityResidual;
metrics.maxAccelerationConstraintResidual = maxAccelerationResidual;
end

function validateRegressionGates(Mechanism, config)
switch config.name
    case 'teaching_four_bar'
        for name = {'E', 'G', 'H'}
            value = speedValue(Mechanism.LinAcc.Joint.(name{1}), config.speedField);
            if max(vecnorm(value(:, 1:2), 2, 2)) <= 1e-10
                error('Verification:TeachingAccelerationRegression', ...
                    'Teaching point %s acceleration regressed to zero.', name{1});
            end
        end

    case 'teaching_slider_crank'
        for name = {'AB', 'BCE'}
            positions = Mechanism.LinkCoM.(name{1});
            if max(vecnorm(positions(:, 1:2) - positions(1, 1:2), 2, 2)) <= 1e-10
                error('Verification:SliderComRegression', ...
                    'Teaching slider CoM %s no longer transports with its link.', name{1});
            end
        end

    case 'slider_crank_tracer'
        velocity = speedValue(Mechanism.LinVel.Joint.D, config.speedField);
        acceleration = speedValue(Mechanism.LinAcc.Joint.D, config.speedField);
        if max(vecnorm(velocity(:, 1:2), 2, 2)) <= 1e-10 || ...
                max(vecnorm(acceleration(:, 1:2), 2, 2)) <= 1e-10
            error('Verification:TracerDerivativeRegression', ...
                'Slider tracer velocity or acceleration regressed to zero.');
        end
end

if any(diff(sign(Mechanism.inputSpeed(:, 1))) ~= 0)
    changes = find(diff(sign(Mechanism.inputSpeed(:, 1))) ~= 0) + 1;
    for i = 1:numel(changes)
        row = changes(i);
        if norm(Mechanism.Joint.B(row, 1:2) - Mechanism.Joint.B(row - 1, 1:2)) > 1e-10
            error('Verification:ToggleBoundaryRegression', ...
                '%s did not retain the duplicated numeric toggle boundary at row %d.', config.name, row);
        end
    end
end
end

function value = speedValue(value, speedField)
if isstruct(value), value = value.(speedField); end
end

function validateTrajectoryStruct(container, rowCount, label)
names = fieldnames(container);
for i = 1:numel(names)
    validateMatrix(container.(names{i}), rowCount, [label '.' names{i}]);
end
end

function validateKinematicStruct(container, rowCount, speedField, label)
names = fieldnames(container);
for i = 1:numel(names)
    value = unwrapSpeed(container.(names{i}), speedField, [label '.' names{i}]);
    validateMatrix(value, rowCount, [label '.' names{i}]);
end
end

function validateDynamics(Mechanism, config, rowCount)
if ~isfield(Mechanism, 'ForceAnalysis')
    error('Verification:MissingDynamics', '%s did not produce force analysis.', config.name);
end

for i = 1:size(config.scenarios, 1)
    scenario = config.scenarios(i, :);
    if scenario(1), forceType = 'Newton'; else, forceType = 'Static'; end
    if scenario(2), gravType = 'Grav'; else, gravType = 'NoGrav'; end
    if scenario(3), frictionType = 'Friction'; else, frictionType = 'NoFriction'; end
    path = sprintf('%s.%s.%s.%s', config.name, forceType, gravType, frictionType);
    result = Mechanism.ForceAnalysis.(forceType).(gravType).(frictionType).(config.speedField);
    validateTrajectoryStruct(result.Joint, rowCount, [path '.Joint']);
    validateMatrix(result.Torque, rowCount, [path '.Torque']);
    validateMatrix(result.NormalForce, rowCount, [path '.NormalForce']);
    if max(abs(result.Torque(:))) == 0
        error('Verification:ZeroDynamics', '%s produced an all-zero torque trace.', path);
    end
end
end

function validateMatrix(value, rowCount, label)
if ~isnumeric(value) || ~isequal(size(value), [rowCount, 3])
    error('Verification:InvalidShape', '%s must be a numeric %d-by-3 matrix.', label, rowCount);
end
if any(~isfinite(value(:)))
    error('Verification:NonFinite', '%s contains non-finite values.', label);
end
end

function position = pointPosition(Mechanism, name)
if strncmp(name, 'CoM.', 4)
    position = Mechanism.LinkCoM.(name(5:end));
elseif isfield(Mechanism.Joint, name)
    position = Mechanism.Joint.(name);
else
    position = Mechanism.TracerPoint.(name);
end
end

function value = pointKinematics(container, name, speedField)
if strncmp(name, 'CoM.', 4)
    value = container.LinkCoM.(name(5:end));
else
    value = container.Joint.(name);
end
value = unwrapSpeed(value, speedField, name);
end

function value = unwrapSpeed(value, speedField, label)
if isstruct(value)
    if ~isfield(value, speedField)
        error('Verification:MissingSpeed', '%s is missing speed field %s.', label, speedField);
    end
    value = value.(speedField);
end
end
