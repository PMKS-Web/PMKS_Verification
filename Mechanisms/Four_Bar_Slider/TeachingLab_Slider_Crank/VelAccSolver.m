function Mechanism = VelAccSolver(Mechanism)
    Mechanism = VelAccSolverUtils.VelAccSolver(Mechanism, @determineAngVel, @determineLinVel, @determineAngAcc, @determineLinAcc);
end

%% Velocity loops
function [Mechanism, AngVel] = determineAngVel(Mechanism, iter, speedStr, JointPos, input_speed)
%velocity equations from given loops

%% Velocity loops
%velocity equations from given loops
syms wBCE V_c
omegaAB=[0 0 input_speed];
omegaBCE=[0 0 wBCE];

A = JointPos.A;
B = JointPos.B;
C = JointPos.C;
theta = Mechanism.Theta;

% A->B->C->D->A
% V_ba + V_cb + V_dc + V_ad = 0
eqn1=VelAccSolverUtils.velSolver(omegaAB,B-A)+VelAccSolverUtils.velSolver(omegaBCE,C-B)-[V_c*cos(theta) V_c*sin(theta) 0]==0;

solution=solve(eqn1,[wBCE, V_c]);

% Store all the determined angular velocities
AngVel.AB=[0 0 input_speed];
AngVel.BCE=[0 0 double(solution.wBCE)]; %angular velocity of BCE

linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.AngVel.(linkNames{i}).(speedStr)(iter,:) = AngVel.(linkNames{i});
end
Mechanism.LinVel.Joint.C.(speedStr)(iter,:) = [double(solution.V_c)*cos(theta) double(solution.V_c)*sin(theta) 0];
end
function [Mechanism] = determineLinVel(Mechanism, iter, speedStr, JointPos, LinkCoMPos, AngVel)
% Determine the velocities at each joint
A = JointPos.A;
B = JointPos.B;
C = JointPos.C;
E = JointPos.E;

AB_com = LinkCoMPos.AB;
BCE_com = LinkCoMPos.BCE;

LinVel.Joint.A = [0 0 0];
LinVel.Joint.B = VelAccSolverUtils.velSolver(AngVel.AB,B-A);
LinVel.Joint.C = Mechanism.LinVel.Joint.C.(speedStr)(iter,:);
LinVel.Joint.E = LinVel.Joint.B;

% Determine the velocities at each link's center of mass
LinVel.LinkCoM.AB = VelAccSolverUtils.velSolver(AngVel.AB,AB_com - A);
LinVel.LinkCoM.BCE = VelAccSolverUtils.velSolver(AngVel.BCE,BCE_com - B) + LinVel.Joint.B;

jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    Mechanism.LinVel.Joint.(jointNames{i}).(speedStr)(iter,:) = LinVel.Joint.(jointNames{i});
end
jointNames = fieldnames(Mechanism.TracerPoint);
for i = 1:length(jointNames)
    Mechanism.LinVel.Joint.(jointNames{i}).(speedStr)(iter,:) = LinVel.Joint.(jointNames{i});
end
% Mechanism.LinVel.Joint.D(iter,:) = LinVel.Joint.D;
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.LinVel.LinkCoM.(linkNames{i}).(speedStr)(iter,:) = LinVel.LinkCoM.(linkNames{i});
end

end
function [Mechanism, AngAcc] = determineAngAcc(Mechanism, iter, speedStr, Pos, AngVel)
%acceleration equations from given loops
syms aBCE A_c
alphaAB=[0 0 0];
alphaBCE=[0 0 aBCE];

A = Pos.A;
B = Pos.B;
C = Pos.C;
% D = Mechanism.TracerPoint.D(iter,:);
theta = Mechanism.Theta;
%% Acceleration loops

% A->B->C->D->A
% A_ba + A_cb + A_dc + A_ad = 0
eqn1=VelAccSolverUtils.accSolver(AngVel.AB,alphaAB, B-A)+VelAccSolverUtils.accSolver(AngVel.BCE,alphaBCE,C-B)-[A_c*cos(theta) A_c*sin(theta) 0]==0;

solution=solve(eqn1,[aBCE A_c]);

% Store all the determined angular accelerations
AngAcc.AB=[0 0 0];
AngAcc.BCE=[0 0 double(solution.aBCE)]; %angular acceleration of BCE

linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.AngAcc.(linkNames{i}).(speedStr)(iter,:) = AngAcc.(linkNames{i});
end
theta = Mechanism.Theta;
Mechanism.LinAcc.Joint.C.(speedStr)(iter,:) = [double(solution.A_c)*cos(theta) double(solution.A_c)*sin(theta) 0];
end
function [Mechanism] = determineLinAcc(Mechanism, iter, speedStr, JointPos, LinkCoMPos, AngVel, AngAcc)
A = JointPos.A;
B = JointPos.B;
C = JointPos.C;
E = JointPos.E;

AB_com = LinkCoMPos.AB;
BCE_com = LinkCoMPos.BCE;

% Determine the accelerations at each joint
LinAcc.Joint.A = [0 0 0];
LinAcc.Joint.B = VelAccSolverUtils.accSolver(AngVel.AB, AngAcc.AB,B-A);
LinAcc.Joint.C = Mechanism.LinAcc.Joint.C.(speedStr)(iter,:);
LinAcc.Joint.E = LinAcc.Joint.B;

% Determine the accelerations at each link's center of mass
LinAcc.LinkCoM.AB = VelAccSolverUtils.accSolver(AngVel.AB,AngAcc.AB,AB_com - A);
LinAcc.LinkCoM.BCE= VelAccSolverUtils.accSolver(AngVel.BCE,AngAcc.BCE,BCE_com - B) + LinAcc.Joint.B;

jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    Mechanism.LinAcc.Joint.(jointNames{i}).(speedStr)(iter,:) = LinAcc.Joint.(jointNames{i});
end
jointNames = fieldnames(Mechanism.TracerPoint);
for i = 1:length(jointNames)
    Mechanism.LinAcc.Joint.(jointNames{i}).(speedStr)(iter,:) = LinAcc.Joint.(jointNames{i});
end
% Mechanism.LinAcc.Joint.D(iter,:) = LinAcc.Joint.D;
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.LinAcc.LinkCoM.(linkNames{i}).(speedStr)(iter,:) = LinAcc.LinkCoM.(linkNames{i});
end
end
