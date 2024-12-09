% Initialization
clear; close all; clc;

% Use the function to find the project root
% currentDir = pwd; % Current directory
% projectRoot = GeneralUtils.findProjectRoot(currentDir, 'PMKS_Simulator_Verification');
% 
% % Specify the path to CommonUtils relative to the project root
% utilsFolderPath = fullfile(projectRoot, 'CommonUtils');
% 
% % Add this path to MATLAB's search paths
% addpath(utilsFolderPath);

currentDir = fileparts(mfilename('fullpath'));

% Construct the path to the 'CommonUtils' directory
utilsFolderPath = fullfile(currentDir, '..', '..', '..', 'CommonUtils');

% Add this path to MATLAB's search paths
addpath(utilsFolderPath);

sensorMap = containers.Map(...
    {'H', 'I'}, ...
    {'d2:5a:50:4a:21:12', 'ef:e4:2c:bf:73:a9'});

% Define paths
witMotionPath = fullfile(pwd, 'Experimental', 'WitMotion');

[input_speed_str, fileToSpeedMap] = SpeedDetermination.determineSpeeds(witMotionPath, sensorMap('H'));

% Initialize Mechanism structure with necessary fields
% Mechanism = struct();
% 
% % Define Coordinates of Joints in 3D Space (x, y, z). Units are mm
% % A = [0, 0, 0];
% % B = [151.97, 0, 0];
% % C = [304.58, 344.73, 0];
% % D = [457.20, 0, 0];
% A = [0, 0, 0];
% B = [1.52, 0, 0];
% C = [4.23, 3.029, 0];
% D = [4.572, 0, 0];
% 
% % Tracer Points for where the sensors are located
% % E = [184.9, 207.46, 0]; % Coolterm, 1
% % F = [90.5, 333.5, 0]; % Coolterm, 2
% % G = [417.98, 193.55, 0]; % Coolterm, 3
% % H = [75.98, 102.78, 0]; % WitMotion, 1
% % I = [417.98, 195.20, 0]; % WitMotion, 2
% E = [4.79, 1.632, 0]; % Coolterm, 2
% F = [2.548, 1.958, 0]; % Coolterm, 3
% G = [2.053, 3.543, 0]; % Coolterm, 1
% H = [0.7598, 1.0278, 0]; % WitMotion, 1
% I = [4.1798, 1.9520, 0]; % WitMotion, 2
% 
% 
% % Define initial joint positions (example values)
% Mechanism.Joint.A = A;
% Mechanism.Joint.B = B;
% Mechanism.Joint.C = C;
% Mechanism.Joint.D = D;
% 
% Mechanism.TracerPoint.E = E; % Coolterm, 1
% Mechanism.TracerPoint.F = F; % Coolterm, 2
% Mechanism.TracerPoint.G = G; % Coolterm, 3
% Mechanism.TracerPoint.H = H; % WitMotion, 1
% Mechanism.TracerPoint.I = I; % WitMotion, 2
% 
% % Define link's center of mass positions
% Mechanism.LinkCoM.ABH = [-6.38, 2.39,0];
% Mechanism.LinkCoM.BCFG = [185.73, 209.10, 0];
% Mechanism.LinkCoM.CDEI = [472.56, -20.80, 0];
% 
% % Define angles for each link
% Mechanism.Angle.Link.ABH = [0 0 rad2deg(atan2((Mechanism.LinkCoM.ABH(2) - A(2)), Mechanism.LinkCoM.ABH(1) - A(1)))];
% Mechanism.Angle.Link.BCFG = [0 0 rad2deg(atan2((Mechanism.LinkCoM.BCFG(2) - B(2)), Mechanism.LinkCoM.BCFG(1) - B(1)))];
% Mechanism.Angle.Link.CDEI = [0 0 rad2deg(atan2((Mechanism.LinkCoM.CDEI(2) - C(2)), Mechanism.LinkCoM.CDEI(1) - C(1)))];
% 
% % Define angles for each sensor
% Mechanism.Angle.Joint.E = [0 0 rad2deg(atan2(E(2) - D(2), E(1) - D(1)))];
% Mechanism.Angle.Joint.F = [0 0 rad2deg(atan2(F(2) - C(2), F(1) - C(1)))+180];
% Mechanism.Angle.Joint.G = [0 0 rad2deg(atan2(G(2) - B(2), G(1) - B(1)))];
% Mechanism.Angle.Joint.H = [0 0 rad2deg(atan2(H(2) - A(2), H(1) - A(1)))];
% Mechanism.Angle.Joint.I = [0 0 rad2deg(atan2(I(2) - D(2), I(1) - D(1)))];
% 
% % Define masses for each link (kg)
% Mechanism.Mass.ABH = 10.458382; 
% Mechanism.Mass.BCFG = 0.626202;
% Mechanism.Mass.CDEI = 4.901229;
% 
% % Define mass moments of inertia for each link
% Mechanism.MassMoI.ABH = 52777966.276354; 
% Mechanism.MassMoI.BCFG = 10871793.503827;
% Mechanism.MassMoI.CDEI = 63343618.03601;
% 
% % Desired for Stress Analysis. Maybe wanna include all the lengths to be
% % utilized within PosSolver
% Mechanism.ABHLength = 10;
% Mechanism.BCFGLength = 10;
% Mechanism.CDEILength = 10;
% 
% % Desired for Stress Analysis. Another idea that is since we know the
% % density, the mass, and the depth of the link, we could determine what the
% % cross sectional area would be. But for now, I think hard coding these
% % values are okay
% Mechanism.crossSectionalAreaABH = 10;
% Mechanism.crossSectionalAreaBCFG = 10;
% Mechanism.crossSectionalAreaCDEI = 10;
% 
% % Define the modulus of elasticity for each link
% Mechanism.modulusElasticity = 10e6;
% 
% % Define angular velocity of the link where a motor is attached
% 
% % input_speed = zeros(1, 2);
% % input_speed(1) = GeneralUtils.rpmToRadPerSec(10.2);
% % input_speed(2) = GeneralUtils.rpmToRadPerSec(20.2);
% % input_speed(3) = GeneralUtils.rpmToRadPerSec(30);
% 
% % Define angular velocity of the link where a motor is attached
% numSpeeds = length(input_speed_str); % Determine the number of speeds
% input_speed = zeros(1, numSpeeds); % Initialize input_speed array
% 
% for i = 1:numSpeeds
%     val = input_speed_str(i); % Convert string to numeric value
%     input_speed(i) = GeneralUtils.rpmToRadPerSec(val); % Convert RPM to rad/sec
% end
% 
% 
% Mechanism.input_speed_str = input_speed_str;
% save('Mechanism.mat', 'Mechanism');
% 
% % Call PosSolver to calculate and store positions
% Mechanism = PosSolver(Mechanism, input_speed);
% save('Mechanism.mat', 'Mechanism');
% 
% % Call VelAccSolver to calculate and store velocities and accelerations
% Mechanism = VelAccSolver(Mechanism);
% save('Mechanism.mat', 'Mechanism');
% 
% % Call ForceSolver to calculate and store forces and torques
%     % Scenarios: [newtonFlag, gravityFlag, frictionFlag]
%     % scenarios = [0 0 0; 0 0 1; 0 1 0; 0 1 1; 1 0 0; 1 0 1; 1 1 0; 1 1 1];
% scenarios = [1 1 0];
% Mechanism = ForceSolver(Mechanism, scenarios);
% save('Mechanism.mat', 'Mechanism');
% % 
% % % Mechanism = StressSolver(Mechanism, scenarios);
% % % save('Mechanism.mat', 'Mechanism');
% % % 
% 
% baseDir = 'Kin';
% csvDir = 'CSVOutput';
% GeneralUtils.exportMatricesToCSV(baseDir, csvDir);
% 
% baseDir = 'Force';
% GeneralUtils.exportMatricesToCSV(baseDir, csvDir);

% baseDir = 'Stress';
% GeneralUtils.exportMatricesToCSV(baseDir, csvDir);

load("Mechanism")


% Define a map from sensors to their respective data types
% sensorDataTypes = containers.Map(...
%     {'E', 'F', 'G', 'H', 'I'}, ...
%     {...
%     {'Angle', 'AngVel'}, ...  % Data types for sensor E
%     {'Angle', 'AngVel'}, ... % Data types for sensor F
%     {'Angle', 'AngVel'}, ... % Data types for sensor G
%     {'Angle', 'AngVel', 'LinAcc'}, ...  % Data types for sensor H
%     {'Angle', 'AngVel', 'LinAcc'}  ... % Data types for sensor I
%     }...
%     );
% 
% sensorSourceMap = containers.Map({'E', 'F', 'G', 'H', 'I'}, ...
%     {'CoolTerm', 'CoolTerm', 'CoolTerm', 'WitMotion', 'WitMotion'});

% Define a map from sensors to their respective data types
sensorDataTypes = containers.Map(...
    {'E', 'F', 'G', 'H', 'I'}, ...
    {...
    {'Angle', 'AngVel'}, ...  % Data types for sensor E
    {'Angle', 'AngVel'}, ... % Data types for sensor F
    {'Angle', 'AngVel'}, ... % Data types for sensor G
    {'Angle', 'AngVel'}, ...  % Data types for sensor H
    {'Angle', 'AngVel'}  ... % Data types for sensor I
    }...
    );

% Create a flat map with sensor-type combinations as keys
sensorDataFlipMap = containers.Map(...
    {'EAngle', 'EAngVel', ...
    'FAngle', 'FAngVel', ...
    'GAngle', 'GAngVel', ...
    'HAngle', 'HAngVel', ...
    'IAngle', 'IAngVel'}, ... % Keys
    [1, 1, ...
    2, 3, ...
    2, 3, ...
    1, 1, ...
    1, 1] ... % Values
);

% Create a flat map with sensor-type combinations as keys
pullColumnDataMap = containers.Map(...
    {'EAngle', 'EAngVel', ...
    'FAngle', 'FAngVel', ...
    'GAngle', 'GAngVel', ...
    'HAngle', 'HAngVel', ...
    'IAngle', 'IAngVel'}, ... % Keys
    [1, 1, ...
    1, 1, ...
    1, 1, ...
    1, 1, ...
    1, 1] ... % Values
);

sensorSourceMap = containers.Map({'E', 'F', 'G', 'H', 'I'}, ...
    {'CoolTerm', 'CoolTerm', 'CoolTerm', 'WitMotion', 'WitMotion'});

sensorInputMap = containers.Map(...
    {'E', 'F', 'G', 'H', 'I'}, ... % Keys
    {'E', 'E', 'E', 'H', 'H'} ... % Values
    );


% sensorDataTypes = containers.Map(...
%     {'H', 'I'}, ...
%     {...
%     {'Angle', 'AngVel'}, ...  % Data types for sensor H
%     {'Angle', 'AngVel'}  ... % Data types for sensor I
%     }...
%     );
% 
% sensorSourceMap = containers.Map({'H', 'I'}, ...
%     {'WitMotion', 'WitMotion'});

% sensorDataTypes = containers.Map(...
%     {'E', 'F', 'G'}, ...
%     {...
%     {'Angle', 'AngVel'}, ...  % Data types for sensor E
%     {'Angle', 'AngVel'}  ... % Data types for sensor F
%     {'Angle', 'AngVel'}  ... % Data types for sensor G
%     }...
%     );
% 

Mechanism = RMSE(Mechanism, fileToSpeedMap, sensorDataTypes, sensorSourceMap, sensorInputMap, sensorDataFlipMap, pullColumnDataMap);