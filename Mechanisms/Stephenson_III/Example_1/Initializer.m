% Initialization
clear; close all; clc;

% Use the function to find the project root
currentDir = pwd; % Current directory
projectRoot = GeneralUtils.findProjectRoot(currentDir, 'PMKS_Simulator_Verification');

% Specify the path to CommonUtils relative to the project root
utilsFolderPath = fullfile(projectRoot, 'CommonUtils');

% Add this path to MATLAB's search paths
addpath(utilsFolderPath);


% Initialize Mechanism structure with necessary fields
Mechanism = struct();

% Initialize Joint positions
A = [1.4 0.485 0];
B = [1.67 0.99 0];
C = [0.255 1.035 0];
D = [0.285 0.055 0];
E = [0.195 2.54 0];
F = [-0.98 2.57 0];
G = [0.05 0.2 0];
H = [-1.714 4.26 0];

% Define initial joint positions (example values)
Mechanism.Joint.A = A;
Mechanism.Joint.B = B;
Mechanism.Joint.C = C;
Mechanism.Joint.D = D;
Mechanism.Joint.E = E;
Mechanism.Joint.F = F;
Mechanism.Joint.G = G;
Mechanism.TracerPoint.H = H;

% Define masses for each link or joint
Mechanism.LinkCoM.AB = Utils.determineCoM([A; B]);
Mechanism.LinkCoM.BC = Utils.determineCoM([B; C]);
Mechanism.LinkCoM.CDE = Utils.determineCoM([D; E]);
Mechanism.LinkCoM.EF = Utils.determineCoM([E; F]);
Mechanism.LinkCoM.FG = Utils.determineCoM([F; H]);

% Define masses for each link
Mechanism.Mass.AB = 5; 
Mechanism.Mass.BC= 10;
Mechanism.Mass.CDE = 5; 
Mechanism.Mass.EF = 10;
Mechanism.Mass.FG = 5; 

% Define mass moments of inertia for each link
Mechanism.MassMoI.AB = 0.1; 
Mechanism.MassMoI.BC = 0.2; 
Mechanism.MassMoI.CDE = 0.1; 
Mechanism.MassMoI.EF = 0.2; 
Mechanism.MassMoI.FG = 0.1; 

% Desired for Stress Analysis. Maybe wanna include all the lengths to be
% utilized within PosSolver
Mechanism.ABELength = 10;
Mechanism.BCFGLength = 10;
Mechanism.CDHLength = 10;

% Desired for Stress Analysis. Another idea that is since we know the
% density, the mass, and the depth of the link, we could determine what the
% cross sectional area would be. But for now, I think hard coding these
% values are okay
Mechanism.crossSectionalAreaABE = 10;
Mechanism.crossSectionalAreaBCFG = 10;
Mechanism.crossSectionalAreaCDH = 10;

% Define the modulus of elasticity for each link
Mechanism.modulusElasticity = 10e6;

% Define angular velocity of the link where a motor is attached
input_speed = 1.0472; % 10 rpm to 1.0472 rad/s
save('Mechanism.mat', 'Mechanism');

% Call PosSolver to calculate and store positions
Mechanism = PosSolver(Mechanism, input_speed);
save('Mechanism.mat', 'Mechanism');

% Call VelAccSolver to calculate and store velocities and accelerations
Mechanism = VelAccSolver(Mechanism);
save('Mechanism.mat', 'Mechanism');

% Call ForceSolver to calculate and store forces and torques
%     % Scenarios: [newtonFlag, gravityFlag, frictionFlag]
%     % scenarios = [0 0 0; 0 0 1; 0 1 0; 0 1 1; 1 0 0; 1 0 1; 1 1 0; 1 1 1];
scenarios = [1 1 0];
Mechanism = ForceSolver(Mechanism, scenarios);
save('Mechanism.mat', 'Mechanism');

Mechanism = StressSolver(Mechanism, scenarios);
save('Mechanism.mat', 'Mechanism');

csvDir = 'CSVOutput';

baseDir = 'Kin';
GeneralUtils.exportMatricesToCSV(baseDir, csvDir);

baseDir = 'Force';
GeneralUtils.exportMatricesToCSV(baseDir, csvDir);

baseDir = 'Stress';
GeneralUtils.exportMatricesToCSV(baseDir, csvDir);
