% Initialization
clear; close all; clc;

% Define coordinates of joints
A = [-3.74, -2.41, 0];
B = [-2.72, 0.91, 0];
C = [1.58, 0.43, 0];
D = [-0.24, 4.01, 0]; 
E = [5.08, 5.31, 0]; 
F = [8.14, 3.35, 0];
G = [7.32, -3.51, 0];
initialJointPositions = struct('A', A, 'B', B, 'C', C, 'D', D, 'E', E, 'F', F, 'G', G);

initialLinkCoMPositions = struct('AB', determineCoM([A, B]), ...
    'BCD', determineCoM([B, C, D]), 'DE', determineCoM([D, E]), ...
    'EF', determineCoM([E, F]), 'CFG', determineCoM([C, F, G]));

max_iterations = 900;

% Initialize positions for maximum iterations
[Mechanism] = initializePositions(initialJointPositions, initialLinkCoMPositions, max_iterations);

% Calculate distances between points
Mechanism = calculateDistances(Mechanism);

% Initialize variables for iteration
[iteration, theta, thetaIncrement] = initializeVariables(Mechanism);

% Initialize angular speed
Mechanism.inputSpeed = zeros(max_iterations, 1);
Mechanism.inputSpeed(1) = 1.0472; % 10 rpm to 1.0472 rad/s

% Main loop for calculating joint positions
[Mechanism, iteration] = calculateJointPositions(Mechanism, theta, thetaIncrement, iteration, max_iterations);

% Create Directory for Saving Results
folderName = 'Kin';
if ~exist(folderName, 'dir')
    mkdir(folderName);  % Create the directory if it doesn't exist
end

% Save Joint Positions in the Created Directory
save(fullfile(folderName, 'Mechanism.mat'), 'Mechanism');

% Function to initialize variables for the simulation
function [iteration, theta, thetaIncrement] = initializeVariables(Mechanism)
iteration = 2;
thetaIncrement = 1; % Angle increment (in degrees)
theta = atan2(Mechanism.Joint.B(1,2) - Mechanism.Joint.A(1,2), Mechanism.Joint.B(1,1) - Mechanism.Joint.A(1,1)); % Initial angle of link AB with adjustment if necessary
end

% Function to initialize positions for all joints for max iterations
function Mechanism = initializePositions(initialMechanismJointPositions, initialMechanismLinkCoMPositions, max_iterations)
jointNames = fieldnames(initialMechanismJointPositions);
for i = 1:length(jointNames)
    initialJointPosition = initialMechanismJointPositions.(jointNames{i});
    Mechanism.Joint.(jointNames{i}) = zeros(max_iterations, 3); % Initialize with zeros
    Mechanism.Joint.(jointNames{i})(1, :) = initialJointPosition; % Set initial position
end
linkNames = fieldnames(initialMechanismLinkCoMPositions);
for i = 1:length(linkNames)
    initialLinkPosition = initialMechanismLinkCoMPositions.(linkNames{i});
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
function [Mechanism, iteration] = calculateJointPositions(Mechanism, theta, thetaIncrement, iteration, max_iterations)
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
% for i = 1:length(jointNames)
%     Mechanism.Joint.(jointNames{i}) = Mechanism.Joint.(jointNames{i})(1:iteration-1, :);
% end
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

Mechanism.LinkCoM.AB(iteration, :) = determineCoM([A; B]);
Mechanism.LinkCoM.BCD(iteration, :) = determineCoM([B; C; D]);
Mechanism.LinkCoM.DE(iteration, :) = determineCoM([D; E]);
Mechanism.LinkCoM.EF(iteration, :) = determineCoM([E; F]);
Mechanism.LinkCoM.CFG(iteration, :) = determineCoM([C; F; G]);

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

function com = determineCoM(poses)
sumX = 0;
sumY = 0;
sumZ = 0;

numPoses = size(poses, 1);
for i = 1:numPoses
    pose = poses(i,:);
    sumX = sumX + pose(1);
    sumY = sumY + pose(2);
    sumZ = sumZ + pose(3);    
end

% Calculate average position
avgX = sumX / numPoses;
avgY = sumY / numPoses;
avgZ = sumZ / numPoses;

com = [avgX, avgY, avgZ];
end