function Mechanism = PosSolver(Mechanism, input_speed)
max_iterations = 900;

% Initialize positions for maximum iterations
[Mechanism] = initializePositions(Mechanism, max_iterations);

% Calculate distances between points
Mechanism = calculateDistances(Mechanism);

% Initialize variables for iteration
[iteration, theta, thetaIncrement] = initializeVariables(Mechanism);

% Initialize angular speed
Mechanism = initializeInputSpeed(Mechanism, input_speed, max_iterations);

% Main loop for calculating joint positions
[Mechanism] = calculateJointPositions(Mechanism, theta, thetaIncrement, iteration, max_iterations);

baseDir = 'Kin/Pos';
% Save joint positions
saveJointPositions(Mechanism, baseDir)
end

% Function to initialize variables for the simulation
function [iteration, theta, thetaIncrement] = initializeVariables(Mechanism)
iteration = 2;
thetaIncrement = 1; % Angle increment (in degrees)
theta = atan2(Mechanism.Joint.B(1,2) - Mechanism.Joint.A(1,2), Mechanism.Joint.B(1,1) - Mechanism.Joint.A(1,1)); % Initial angle of link AB with adjustment if necessary
end

% Function to initialize positions for all joints for max iterations
function Mechanism = initializePositions(Mechanism, max_iterations)
jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    initialJointPosition = Mechanism.Joint.(jointNames{i});
    Mechanism.Joint.(jointNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
    Mechanism.Joint.(jointNames{i})(1, :) = initialJointPosition; % Set initial position
end
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    initialLinkPosition = Mechanism.LinkCoM.(linkNames{i});
    Mechanism.LinkCoM.(linkNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
    Mechanism.LinkCoM.(linkNames{i})(1, :) = initialLinkPosition; % Set initial position
end
end

% Function to calculate distances between joints
function Mechanism = calculateDistances(Mechanism)
% Distance Between Points
% Link AB
Mechanism.LinkLength.AB = norm(Mechanism.Joint.B - Mechanism.Joint.A);
% Link BCD
Mechanism.LinkLength.BC = norm(Mechanism.Joint.C - Mechanism.Joint.B);
Mechanism.LinkLength.BD = norm(Mechanism.Joint.D - Mechanism.Joint.B);
Mechanism.LinkLength.CD = norm(Mechanism.Joint.D - Mechanism.Joint.C);
% Link DE
Mechanism.LinkLength.DE = norm(Mechanism.Joint.E - Mechanism.Joint.D);
% Link EF
Mechanism.LinkLength.EF = norm(Mechanism.Joint.F - Mechanism.Joint.E);
% Link FCG
Mechanism.LinkLength.CF = norm(Mechanism.Joint.F - Mechanism.Joint.C);
Mechanism.LinkLength.CG = norm(Mechanism.Joint.G - Mechanism.Joint.C);
Mechanism.LinkLength.FG = norm(Mechanism.Joint.G - Mechanism.Joint.F);
end

% Main function to calculate joint positions through iterations
function [Mechanism] = calculateJointPositions(Mechanism, theta, thetaIncrement, iteration, max_iterations)
forwardDir = true; % Flag to indicate the direction of rotation. Mechanism should be going forward on its last iteration

while ~(determineEqual(Mechanism.Joint.B(1, :), Mechanism.Joint.B(iteration - 1, :)) && ...
        ~isequal(iteration, 2) && forwardDir) && iteration < max_iterations
    [Mechanism, theta, thetaIncrement, forwardDir, iteration] = updateJointPositions(Mechanism, theta, thetaIncrement, iteration, forwardDir);
end

% Trim positions and speeds to the last filled iteration
jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    Mechanism.Joint.(jointNames{i}) = Mechanism.Joint.(jointNames{i})(1:iteration-1, :);
end
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.LinkCoM.(linkNames{i}) = Mechanism.LinkCoM.(linkNames{i})(1:iteration-1,:);
end
Mechanism.inputSpeed= Mechanism.inputSpeed(1:iteration-1,:);
end

% Function to update positions based on current state
function [Mechanism, theta, thetaIncrement, forwardDir, iteration] = updateJointPositions(Mechanism, theta, thetaIncrement, iteration, forwardDir)
% Calculate current joint angles
theta = theta + deg2rad(thetaIncrement);

% Calculate new positions for joints
[Mechanism, valid, theta, iteration] = calculateNewPositions(Mechanism, theta, iteration, forwardDir);
if ~valid
    % Revert theta if new positions are invalid and flip direction
    thetaIncrement = thetaIncrement * -1;
    forwardDir = ~forwardDir;
end
end

% Function to calculate new positions for the joints
function [Mechanism, valid, theta, iteration] = calculateNewPositions(Mechanism, theta, iteration, forwardDir)
% Initialize validity flag
valid = true;

A = Mechanism.Joint.A(1, :);
G = Mechanism.Joint.G(1,:);

% Direct calculation for B
B = [A(1) + Mechanism.LinkLength.AB * cos(theta), A(2) + Mechanism.LinkLength.AB * sin(theta), 0];

% Circle-circle intersections for C, D, E, F
C = circleCircleIntersection(B(1), B(2), Mechanism.LinkLength.BC, G(1), G(2), Mechanism.LinkLength.CG, Mechanism.Joint.C(iteration - 1, 1), Mechanism.Joint.C(iteration - 1, 2));
if isempty(C), valid = false; return; end

D = circleCircleIntersection(B(1), B(2), Mechanism.LinkLength.BD, C(1), C(2), Mechanism.LinkLength.CD, Mechanism.Joint.D(iteration - 1, 1), Mechanism.Joint.D(iteration - 1, 2));
if isempty(D), valid = false; return; end

F = circleCircleIntersection(C(1), C(2), Mechanism.LinkLength.CF, G(1), G(2), Mechanism.LinkLength.FG, Mechanism.Joint.F(iteration - 1, 1), Mechanism.Joint.F(iteration - 1, 2));
if isempty(F), valid = false; return; end

E = circleCircleIntersection(D(1), D(2), Mechanism.LinkLength.DE, F(1), F(2), Mechanism.LinkLength.EF, Mechanism.Joint.E(iteration - 1, 1), Mechanism.Joint.E(iteration - 1, 2));
if isempty(E), valid = false; return; end

% Update positions
Mechanism.Joint.A(iteration, :) = A;
Mechanism.Joint.B(iteration, :) = B;
Mechanism.Joint.C(iteration, :) = C;
Mechanism.Joint.D(iteration, :) = D;
Mechanism.Joint.E(iteration, :) = E;
Mechanism.Joint.F(iteration, :) = F;
Mechanism.Joint.G(iteration, :) = G;

utilsFolderPath = fullfile(pwd);
addpath(utilsFolderPath);

Mechanism.LinkCoM.AB(iteration, :) = Utils.determineCoM([A; B]);
Mechanism.LinkCoM.BCD(iteration, :) = Utils.determineCoM([B; C; D]);
Mechanism.LinkCoM.DE(iteration, :) = Utils.determineCoM([D; E]);
Mechanism.LinkCoM.EF(iteration, :) = Utils.determineCoM([E; F]);
Mechanism.LinkCoM.CFG(iteration, :) = Utils.determineCoM([C; F; G]);

if (forwardDir)
    Mechanism.inputSpeed(iteration) = Mechanism.inputSpeed(1);
else
    Mechanism.inputSpeed(iteration) = Mechanism.inputSpeed(1) * -1;
end
iteration = iteration + 1;
end

% Utility function for circle-circle intersection calculation
function result = circleCircleIntersection(x1, y1, r1, x2, y2, r2, pointX, pointY)
% Find intersection points
[xIntersect, yIntersect] = circcirc(x1, y1, r1, x2, y2, r2);

% Check if the intersection points are determined
if isempty(xIntersect) || isempty(yIntersect)
    result = [];
    return;
end

if isnan(xIntersect(1)) || isnan(yIntersect(1))
    result = [];
    return;
end

% Calculate distances from intersection points to the given point
dist1 = sqrt((xIntersect(1) - pointX)^2 + (yIntersect(1) - pointY)^2);
dist2 = sqrt((xIntersect(2) - pointX)^2 + (yIntersect(2) - pointY)^2);

% Determine the closest intersection point
if dist1 < dist2
    result = [xIntersect(1) yIntersect(1) 0];
else
    result = [xIntersect(2) yIntersect(2) 0];
end
end

% Utility function to check if two arrays are approximately equal
function result = determineEqual(arr1, arr2)
tolerance = 0.001;
result = all(abs(arr1 - arr2) < tolerance);
end

function saveJointPositions(Mechanism, baseDir)

% Create Directory for Saving Results
folderName = 'Kin';
if ~exist(folderName, 'dir')
    mkdir(folderName);  % Create the directory if it doesn't exist
end

% Save Joint Positions in the Created Directory
save('Mechanism.mat', 'Mechanism');


jointNames = fieldnames(Mechanism.Joint);
jointFolder = fullfile(baseDir, 'Joint');
if ~exist(jointFolder, 'dir')
    mkdir(jointFolder);
end

for i = 1:length(jointNames)
    jointName = jointNames{i};
    % Create a temporary struct with the field name as the joint name
    tempStruct = struct(jointName, Mechanism.Joint.(jointName));
    % Save this struct using the -struct option
    save(fullfile(jointFolder, jointName), '-struct', 'tempStruct', jointName);
end

% Save link CoM positions
linkNames = fieldnames(Mechanism.LinkCoM);
linkCoMFolder = fullfile(baseDir, 'LinkCoM');
if ~exist(linkCoMFolder, 'dir')
    mkdir(linkCoMFolder);
end

for i = 1:length(linkNames)
    linkName = linkNames{i};
    % Create a temporary struct with the field name as the link name
    tempStruct = struct(linkName, Mechanism.LinkCoM.(linkName));
    % Save this struct using the -struct option
    save(fullfile(linkCoMFolder, linkName), '-struct', 'tempStruct', linkName);
end
end

function Mechanism = initializeInputSpeed(Mechanism, input_speed, max_iterations)
Mechanism.inputSpeed = zeros(max_iterations, 1);
Mechanism.inputSpeed(1) = input_speed; % 10 rpm to 1.0472 rad/s
end