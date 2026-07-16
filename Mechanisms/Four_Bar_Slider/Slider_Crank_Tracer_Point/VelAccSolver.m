function Mechanism = VelAccSolver(Mechanism)

% Determine the number of iterations (rows in Joints)
numIterations = size(Mechanism.Joint.A, 1); % Assuming 'A' is a joint in Mechanism.Joints

% Initialize fields for storing kinematics data
Mechanism.AngVel = struct();
Mechanism.LinVel = struct();
Mechanism.AngAcc = struct();
Mechanism.LinAcc = struct();

blankVector = [0 0 0];
initialBlankJointVector = struct('A', blankVector, ...
    'B', blankVector, 'C', blankVector, 'D', blankVector);

initialBlankLinkVector= struct('AB', blankVector, ...
    'BCD', blankVector);

[Mechanism] = initializeAngVels(Mechanism, initialBlankLinkVector, numIterations);
[Mechanism] = initializeLinVels(Mechanism, initialBlankJointVector, initialBlankLinkVector, numIterations);
[Mechanism] = initializeAngAccs(Mechanism, initialBlankLinkVector, numIterations);
[Mechanism] = initializeLinAccs(Mechanism, initialBlankJointVector, initialBlankLinkVector, numIterations);

% Iterate through all iterations
for iter = 1:numIterations
    % Extract joint positions for this iteration
    JointPos = extractJointPositions(Mechanism, iter);
    LinkCoMPos = extractLinkCoMPositions(Mechanism, iter);

    % Assuming input_speed is defined or extracted from Mechanism
    input_speed = Mechanism.inputSpeed(iter); % Placeholder, adjust based on your Mechanism structure

    % Calculate kinematics for the current iteration and store within the Mechanism
    Mechanism = determineKinematics(Mechanism, iter, JointPos, LinkCoMPos, input_speed);
end
% end

% Save the updated Mechanism
save('Mechanism.mat', 'Mechanism');

% Define the base folder name for Velocities and Accelerations
baseVelFolder = 'Kin/Vel';
baseAccFolder = 'Kin/Acc';

% Directories for velocities
linVelJointFolder = fullfile(baseVelFolder, 'LinVel', 'Joint');
linVelLinkCoMFolder = fullfile(baseVelFolder, 'LinVel', 'LinkCoM');
angVelFolder = fullfile(baseVelFolder, 'AngVel');

% Directories for accelerations
linAccJointFolder = fullfile(baseAccFolder, 'LinAcc', 'Joint');
linAccLinkCoMFolder = fullfile(baseAccFolder, 'LinAcc', 'LinkCoM');
angAccFolder = fullfile(baseAccFolder, 'AngAcc');

% Create the directories if they don't exist
folders = {linVelJointFolder, linVelLinkCoMFolder, angVelFolder, linAccJointFolder, linAccLinkCoMFolder, angAccFolder};
for i = 1:length(folders)
    if ~exist(folders{i}, 'dir')
        mkdir(folders{i});
    end
end

% Example usage:
saveData(linVelJointFolder, Mechanism.LinVel.Joint);
saveData(linVelLinkCoMFolder, Mechanism.LinVel.LinkCoM);
saveData(angVelFolder, Mechanism.AngVel);
saveData(linAccJointFolder, Mechanism.LinAcc.Joint);
saveData(linAccLinkCoMFolder, Mechanism.LinAcc.LinkCoM);
saveData(angAccFolder, Mechanism.AngAcc);

end

function JointPos = extractJointPositions(Mechanism, iteration)
% Extract joint positions for a specific iteration
JointPos = struct();
jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    JointPos.(jointNames{i}) = Mechanism.Joint.(jointNames{i})(iteration, :);
end
end
function LinkCoMPos = extractLinkCoMPositions(Mechanism, iteration)
% Extract link center of mass positions for a specific iteration
LinkCoMPos = struct();
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    LinkCoMPos.(linkNames{i}) = Mechanism.LinkCoM.(linkNames{i})(iteration, :);
end
end

function Mechanism = determineKinematics(Mechanism, iter, JointPos, LinkCoMPos, input_speed)
% Placeholder for your logic to calculate kinematics
[Mechanism, AngVel] = determineAngVel(Mechanism, iter, JointPos, input_speed);
[Mechanism] = determineLinVel(Mechanism, iter, JointPos, LinkCoMPos, AngVel);
[Mechanism, AngAcc] = determineAngAcc(Mechanism, iter, JointPos, AngVel);
[Mechanism] = determineLinAcc(Mechanism, iter, JointPos, LinkCoMPos, AngVel, AngAcc);
end

%% Velocity loops
function [Mechanism, AngVel] = determineAngVel(Mechanism, iter, JointPos, input_speed)
%velocity equations from given loops
A = JointPos.A;
B = JointPos.B;
C = JointPos.C;
D = Mechanism.TracerPoint.D(iter,:);

%% Velocity loops
%velocity equations from given loops
syms wBCD V_c
omegaAB=[0 0 input_speed];
omegaBCD=[0 0 wBCD];

% A->B->C->D->A
% V_ba + V_cb + V_dc + V_ad = 0
eqn1=velSolver(omegaAB,B-A)+velSolver(omegaBCD,C-B)-[V_c*cos(0) V_c*sin(0) 0]==0;
solution=solve(eqn1,[wBCD, V_c]);

% Store all the determined angular velocities
AngVel.AB=[0 0 input_speed];
AngVel.BCD=[0 0 double(solution.wBCD)]; %angular velocity of BCD

linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.AngVel.(linkNames{i})(iter,:) = AngVel.(linkNames{i});
end
Mechanism.LinVel.Joint.C(iter,:) = [solution.V_c*cos(0) solution.V_c*sin(0) 0];
end
function [Mechanism] = determineLinVel(Mechanism, iter, JointPos, LinkCoMPos, AngVel)
% Determine the velocities at each joint
A = JointPos.A;
B = JointPos.B;
% C = JointPos.C;
D = Mechanism.TracerPoint.D(iter,:);

AB_com = LinkCoMPos.AB;
BCD_com = LinkCoMPos.BCD;

LinVel.Joint.A = [0 0 0];
LinVel.Joint.B = velSolver(AngVel.AB,B-A);
LinVel.Joint.C = Mechanism.LinVel.Joint.C(iter,:);
% LinVel.Joint.C = velSolver(AngVel.CDE,);
LinVel.Joint.D = velSolver(AngVel.BCD, D-B) + LinVel.Joint.B;

% Determine the velocities at each link's center of mass
LinVel.LinkCoM.AB = velSolver(AngVel.AB,AB_com - A);
LinVel.LinkCoM.BCD= velSolver(AngVel.BCD,BCD_com - B) + LinVel.Joint.B;

jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    Mechanism.LinVel.Joint.(jointNames{i})(iter,:) = LinVel.Joint.(jointNames{i});
end
Mechanism.LinVel.Joint.D(iter,:) = LinVel.Joint.D;
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.LinVel.LinkCoM.(linkNames{i})(iter,:) = LinVel.LinkCoM.(linkNames{i});
end

end
function [Mechanism, AngAcc] = determineAngAcc(Mechanism, iter, Pos, AngVel)
%acceleration equations from given loops
syms aBCD A_c
alphaAB=[0 0 0];
alphaBCD=[0 0 aBCD];

A = Pos.A;
B = Pos.B;
C = Pos.C;
D = Mechanism.TracerPoint.D(iter,:);
%% Acceleration loops

% A->B->C->D->A
% A_ba + A_cb + A_dc + A_ad = 0
eqn1=accSolver(AngVel.AB,alphaAB, B-A)+accSolver(AngVel.BCD,alphaBCD,C-B)-[A_c*cos(0) A_c*sin(0) 0]==0;

solution=solve(eqn1,[aBCD A_c]);

% Store all the determined angular accelerations
AngAcc.AB=[0 0 0];
AngAcc.BCD=[0 0 double(solution.aBCD)]; %angular acceleration of BC

linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.AngAcc.(linkNames{i})(iter,:) = AngAcc.(linkNames{i});
end
Mechanism.LinAcc.Joint.C(iter,:) = [solution.A_c*cos(0) solution.A_c*sin(0) 0];
end
function [Mechanism] = determineLinAcc(Mechanism, iter, JointPos, LinkCoMPos, AngVel, AngAcc)
A = JointPos.A;
B = JointPos.B;
C = JointPos.C;
D = Mechanism.TracerPoint.D(iter,:);

AB_com = LinkCoMPos.AB;
BCD_com = LinkCoMPos.BCD;

% Determine the accelerations at each joint
LinAcc.Joint.A = [0 0 0];
LinAcc.Joint.B = accSolver(AngVel.AB, AngAcc.AB,B-A);
LinAcc.Joint.C = Mechanism.LinAcc.Joint.C(iter,:);
% LinAcc.Joint.C = accSolver(AngVel.BCD, AngAcc.BCD,C-B) + LinAcc.Joint.B;
LinAcc.Joint.D = accSolver(AngVel.BCD, AngAcc.BCD,D-B) + LinAcc.Joint.B;

% Determine the accelerations at each link's center of mass
LinAcc.LinkCoM.AB = accSolver(AngVel.AB,AngAcc.AB,AB_com - A);
LinAcc.LinkCoM.BCD= accSolver(AngVel.BCD,AngAcc.BCD,BCD_com - B) + LinAcc.Joint.B;

jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    Mechanism.LinAcc.Joint.(jointNames{i})(iter,:) = LinAcc.Joint.(jointNames{i});
end
Mechanism.LinAcc.Joint.D(iter,:) = LinAcc.Joint.D;
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.LinAcc.LinkCoM.(linkNames{i})(iter,:) = LinAcc.LinkCoM.(linkNames{i});
end
end

% Desired functions to do cross products appropriately
function vel = velSolver(w, r)
vel = cross(w,r);
end
function acc = accSolver(w,a,r)
acc = cross(w,cross(w,r)) + cross(a,r);
end

% Initialize AngVel, LinVel, AngAcc, LinAcc
function Mechanism = initializeAngVels(Mechanism, initialBlankLinkVector, max_iterations)
angVelNames = fieldnames(initialBlankLinkVector);
for i = 1:length(angVelNames)
    Mechanism.AngVel.(angVelNames{i}) = zeros(max_iterations, 3); % Initialize with zeros for each dimension (assuming 3D angular velocities)
end
end
function Mechanism = initializeLinVels(Mechanism, initialBlankJointVector, initialBlankLinkVector, max_iterations)
linJointVelNames = fieldnames(initialBlankJointVector);
for i = 1:length(linJointVelNames)
    Mechanism.LinVel.Joint.(linJointVelNames{i}) = zeros(max_iterations, 3); % Initialize with zeros for each dimension (assuming 3D angular velocities)
end
linLinkCoMVelNames = fieldnames(initialBlankLinkVector);
for i = 1:length(linLinkCoMVelNames)
    Mechanism.LinVel.LinkCoM.(linLinkCoMVelNames{i}) = zeros(max_iterations, 3); % Initialize with zeros for each dimension (assuming 3D angular velocities)
end
end
function Mechanism = initializeAngAccs(Mechanism, initialBlankLinkVector, max_iterations)
angAccNames = fieldnames(initialBlankLinkVector);
for i = 1:length(angAccNames)
    Mechanism.AngAcc.(angAccNames{i}) = zeros(max_iterations, 3); % Initialize with zeros for each dimension (assuming 3D angular velocities)
end
end
function Mechanism = initializeLinAccs(Mechanism, initialBlankJointVector, initialBlankLinkVector, max_iterations)
linJointNames = fieldnames(initialBlankJointVector);
for i = 1:length(linJointNames)
    Mechanism.LinAcc.Joint.(linJointNames{i}) = zeros(max_iterations, 3); % Initialize with zeros for each dimension (assuming 3D angular velocities)
end
linLinkCoMAccNames = fieldnames(initialBlankLinkVector);
for i = 1:length(linLinkCoMAccNames)
    Mechanism.LinAcc.LinkCoM.(linLinkCoMAccNames{i}) = zeros(max_iterations, 3); % Initialize with zeros for each dimension (assuming 3D angular velocities)
end
end

% Save function for clarity and reusability
function saveData(folder, dataStruct)
% Ensure the folder exists
if ~exist(folder, 'dir')
    mkdir(folder);
end

names = fieldnames(dataStruct); % Get all field names of the structure
for i = 1:length(names)
    name = names{i};
    data = dataStruct.(name); % Extract data

    % Create a temporary struct with the extracted data
    tempStruct = struct(name, data);

    % Correctly use the -struct option by providing the variable name of the temporary struct
    save(fullfile(folder, name), '-struct', 'tempStruct', name);
end
end

% clc;
% close all
% clear all;
%
% %%
% load('Kin/Pos/A')
% load('Kin/Pos/B')
% load('Kin/Pos/C')
% load('Kin/Pos/D')
% load('Kin/Pos/E')
% load('Kin/Pos/F')
% load('Kin/Pos/G')
%
% WAB=zeros(10,3);
% WBC=zeros(10,3);
% WDCE=zeros(10,3);
% WEF=zeros(10,3);
% WFG=zeros(10,3);
%
% V_a=zeros(10,3);
% V_b=zeros(10,3);
% V_c=zeros(10,3);
% V_d=zeros(10,3);
% V_e=zeros(10,3);
% V_f=zeros(10,3);
% V_g=zeros(10,3);
%
% V_ab_com=zeros(10,3);
% V_bc_com=zeros(10,3);
% V_dce_com=zeros(10,3);
% V_ef_com=zeros(10,3);
% V_fg_com=zeros(10,3);
%
% AAB=zeros(10,3);
% ABC=zeros(10,3);
% ADCE=zeros(10,3);
% AEF=zeros(10,3);
% AFG=zeros(10,3);
%
% A_a=zeros(10,3);
% A_b=zeros(10,3);
% A_c=zeros(10,3);
% A_d=zeros(10,3);
% A_e=zeros(10,3);
% A_f=zeros(10,3);
% A_g=zeros(10,3);
%
% A_ab_com=zeros(10,3);
% A_bc_com=zeros(10,3);
% A_dce_com=zeros(10,3);
% A_ef_com=zeros(10,3);
% A_fg_com=zeros(10,3);
%
% for theta=1:1:10
%     % Coordinates of joints
%     A = A_vec(theta,:);
%     B = B_vec(theta,:);
%     C = C_vec(theta,:);
%     D = D_vec(theta,:);
%     E = E_vec(theta,:);
%     F = F_vec(theta,:);
%     G = G_vec(theta,:);
%
%     % Centers of Mass of each Link
%     AB_com = (A+B)/2;
%     BC_com = (B+C)/2;
%     DCE_com = (C+D+E)/3;
%     EF_com = (E+F)/2;
%     FG_com = (F+G)/2;
%
%     %% Velocity loops
%     %velocity equations from given loops
%     syms wBC wDCE wEF wFG
%     omegaAB=[0 0 1.8589];
%     omegaBC=[0 0 wBC];
%     omegaDCE=[0 0 wDCE];
%     omegaEF=[0 0 wEF];
%     omegaFG=[0 0 wFG];
%
%     % A->B->C->D->A
%     % V_ba + V_cb + V_dc + V_ad = 0
%     eqn1=velSolver(omegaAB,B-A)+velSolver(omegaBC,C-B)+velSolver(omegaDCE,D-C)==0;
%
%     % D->E->F->G->D
%     % V_ed + V_fe + V_gf + V_dg = 0
%     eqn2=velSolver(omegaDCE,E-D)+velSolver(omegaEF,F-E)+velSolver(omegaFG,G-F)==0;
%
%     solution=solve([eqn1, eqn2],[wBC wDCE wEF wFG]);
%
%     % Store all the determined angular velocities
%     WAB(theta,:)=[0 0 1.8589];
%     WBC(theta,:)=[0 0 solution.wBC]; %angular velocity of BC
%     WDCE(theta,:)=[0 0 solution.wDCE]; %angular velocity of DCE
%     WEF(theta,:)=[0 0 solution.wEF]; %angular velocity of EF
%     WFG(theta,:)=[0 0 solution.wFG]; %angular velocity of FG
%
%
%     % Determine the velocities at each joint
%     V_a(theta,:) = [0 0 0];
%     V_b(theta,:) = velSolver(WAB(theta,:),B-A);
%     V_c(theta,:) = velSolver(WDCE(theta,:),C-D);
%     V_d(theta,:) = [0 0 0];
%     V_e(theta,:) = velSolver(WDCE(theta,:),E-D);
%     V_f(theta,:) = velSolver(WFG(theta,:),F-G);
%     V_g(theta,:) = [0 0 0];
%
%     % Determine the velocities at each link's center of mass
%     V_ab_com(theta,:) = velSolver(WAB(theta,:),AB_com - A);
%     V_bc_com(theta,:) =  velSolver(WBC(theta,:),BC_com - B) + V_b(theta,:);
%     V_dce_com(theta,:) = velSolver(WDCE(theta,:),DCE_com - D);
%     V_ef_com(theta,:) =  velSolver(WEF(theta,:),EF_com - E) + V_e(theta,:);
%     V_fg_com(theta,:) = velSolver(WFG(theta,:),FG_com - G);
%
%     %% Acceleration loops
%     %acceleration equations from given loops
%     syms aBC aDCE aEF aFG
%     alphaAB=[0 0 0];
%     alphaBC=[0 0 aBC];
%     alphaDCE=[0 0 aDCE];
%     alphaEF=[0 0 aEF];
%     alphaFG=[0 0 aFG];
%
%     % A->B->C->D->A
%     % A_ba + A_cb + A_dc + A_ad = 0
%     eqn1=accSolver(WAB(theta,:),alphaAB, B-A)+accSolver(WBC(theta,:),alphaBC,C-B)+accSolver(WDCE(theta,:),alphaDCE,D-C)==0;
%
%     % D->E->F->G->D
%     % A_ed + A_fe + A_gf + A_dg = 0
%     eqn2=accSolver(WDCE(theta,:),alphaDCE,E-D)+accSolver(WEF(theta,:),alphaEF,F-E)+accSolver(WFG(theta,:),alphaFG,G-F)==0;
%
%     solution=solve([eqn1, eqn2],[aBC aDCE aEF aFG]);
%
%     % Store all the determined angular accelerations
%     AAB(theta,:)=[0 0 0];
%     ABC(theta,:)=[0 0 solution.aBC]; %angular acceleration of BC
%     ADCE(theta,:)=[0 0 solution.aDCE]; %angular acceleration of DCE
%     AEF(theta,:)=[0 0 solution.aEF]; %angular acceleration of EF
%     AFG(theta,:)=[0 0 solution.aFG]; %angular acceleration of FG
%
%
%     % Determine the accelerations at each joint
%     A_a(theta,:) = [0 0 0];
%     A_b(theta,:) = accSolver(WAB(theta,:), AAB(theta,:),B-A);
%     A_c(theta,:) = accSolver(WBC(theta,:), ABC(theta,:),C-D);
%     A_d(theta,:) = [0 0 0];
%     A_e(theta,:) = accSolver(WDCE(theta,:), ADCE(theta,:),E-D);
%     A_f(theta,:) = accSolver(WFG(theta,:),AFG(theta,:),F-G);
%     A_g(theta,:) = [0 0 0];
%
%     % Determine the accelerations at each link's center of mass
%     A_ab_com(theta,:) = accSolver(WAB(theta,:),AAB(theta,:),AB_com - A);
%     A_bc_com(theta,:) =  accSolver(WBC(theta,:),ABC(theta,:),BC_com - B) + A_b(theta,:);
%     A_dce_com(theta,:) = accSolver(WDCE(theta,:),ADCE(theta,:),DCE_com - D);
%     A_ef_com(theta,:) =  accSolver(WEF(theta,:),AEF(theta,:),EF_com - E) + A_e(theta,:);
%     A_fg_com(theta,:) = accSolver(WFG(theta,:),AFG(theta,:),FG_com - G);
% end
%
% % Directory for saving the results
% checkDirectory('Kin/LinVel/Joint');
% checkDirectory('Kin/LinVel/Link');
% checkDirectory('Kin/AngVel');
% checkDirectory('Kin/LinAcc/Joint');
% checkDirectory('Kin/LinAcc/Link');
% checkDirectory('Kin/AngAcc');
%
% save('Kin/LinVel/Joint/A', 'V_a')
% save('Kin/LinVel/Joint/B', 'V_b')
% save('Kin/LinVel/Joint/C', 'V_c')
% save('Kin/LinVel/Joint/D', 'V_d')
% save('Kin/LinVel/Joint/E', 'V_e')
% save('Kin/LinVel/Joint/F', 'V_f')
% save('Kin/LinVel/Joint/G', 'V_g')
%
% save('Kin/LinVel/Link/AB', 'V_ab_com')
% save('Kin/LinVel/Link/BC', 'V_bc_com')
% save('Kin/LinVel/Link/DCE', 'V_dce_com')
% save('Kin/LinVel/Link/EF', 'V_ef_com')
% save('Kin/LinVel/Link/FG', 'V_fg_com')
%
% save('Kin/AngVel/AB', 'WAB')
% save('Kin/AngVel/BC', 'WBC')
% save('Kin/AngVel/DCE', 'WDCE')
% save('Kin/AngVel/EF', 'WEF')
% save('Kin/AngVel/FG', 'WFG')
%
% save('Kin/LinAcc/Joint/A', 'A_a')
% save('Kin/LinAcc/Joint/B', 'A_b')
% save('Kin/LinAcc/Joint/C', 'A_c')
% save('Kin/LinAcc/Joint/D', 'A_d')
% save('Kin/LinAcc/Joint/E', 'A_e')
% save('Kin/LinAcc/Joint/F', 'A_f')
% save('Kin/LinAcc/Joint/G', 'A_g')
%
% save('Kin/LinAcc/Link/AB', 'A_ab_com')
% save('Kin/LinAcc/Link/BC', 'A_bc_com')
% save('Kin/LinAcc/Link/DCE', 'A_dce_com')
% save('Kin/LinAcc/Link/EF', 'A_ef_com')
% save('Kin/LinAcc/Link/FG', 'A_fg_com')
%
% save('Kin/AngAcc/AB', 'AAB')
% save('Kin/AngAcc/BC', 'ABC')
% save('Kin/AngAcc/DCE', 'ADCE')
% save('Kin/AngAcc/EF', 'AEF')
% save('Kin/AngAcc/FG', 'AFG')
%
% function vel = velSolver(w, r)
% vel = cross(w,r);
% end
%
% function acc = accSolver(w,a,r)
% acc = cross(w,cross(w,r)) + cross(a,r);
% end
%
% function checkDirectory(saveDir)
% % Check if the directory exists, if not, create it
% if ~exist(saveDir, 'dir')
%     mkdir(saveDir);
% end
% end
