function Mechanism = VelAccSolver(Mechanism)
    Mechanism = VelAccSolverUtils.VelAccSolver(Mechanism, @determineAngVel, @determineLinVel, @determineAngAcc, @determineLinAcc);
end

%% Velocity loops
function [Mechanism, AngVel] = determineAngVel(Mechanism, iter, speedStr, JointPos, input_speed)
%velocity equations from given loops
syms wBCE wCD wEF wFG
omegaAB=[0 0 input_speed];
omegaBCE=[0 0 wBCE];
omegaCD=[0 0 wCD];
omegaEF=[0 0 wEF];
omegaFG=[0 0 wFG];

A = JointPos.A;
B = JointPos.B;
C = JointPos.C;
D = JointPos.D;
E = JointPos.E;
F = JointPos.F;
G = JointPos.G;

% A->B->C->D->A
% V_ba + V_cb + V_dc + V_ad = 0
eqn1=VelAccSolverUtils.velSolver(omegaAB,B-A)+VelAccSolverUtils.velSolver(omegaBCE,C-B)+VelAccSolverUtils.velSolver(omegaCD,D-C)==0;

% A->B->E->F->G->A
% V_ba + V_eb + V_fe + V_gf + V_ag = 0
eqn2=VelAccSolverUtils.velSolver(omegaAB,B-A)+VelAccSolverUtils.velSolver(omegaBCE,E-B)+VelAccSolverUtils.velSolver(omegaEF,F-E)+VelAccSolverUtils.velSolver(omegaFG,G-F)==0;

solution=solve([eqn1, eqn2],[wBCE wCD wEF wFG]);

% Store all the determined angular velocities
AngVel.AB=[0 0 input_speed];
AngVel.BCE=[0 0 double(solution.wBCE)]; %angular velocity of BCE
AngVel.CD=[0 0 double(solution.wCD)]; %angular velocity of DE
AngVel.EF=[0 0 double(solution.wEF)]; %angular velocity of EF
AngVel.FG=[0 0 double(solution.wFG)]; %angular velocity of CFG

linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.AngVel.(linkNames{i}).(speedStr)(iter,:) = AngVel.(linkNames{i});
end
end
function [Mechanism] = determineLinVel(Mechanism, iter, speedStr, JointPos, LinkCoMPos, AngVel)
% Determine the velocities at each joint
A = JointPos.A;
B = JointPos.B;
C = JointPos.C;
D = JointPos.D;
E = JointPos.E;
F = JointPos.F;
G = JointPos.G;

AB_com = LinkCoMPos.AB;
BCE_com = LinkCoMPos.BCE;
CD_com = LinkCoMPos.CD;
EF_com = LinkCoMPos.EF;
FG_com = LinkCoMPos.FG;

LinVel.Joint.A = [0 0 0];
LinVel.Joint.B = VelAccSolverUtils.velSolver(AngVel.AB,B-A);
LinVel.Joint.C = VelAccSolverUtils.velSolver(AngVel.CD,C-D);
LinVel.Joint.D = [0 0 0];
LinVel.Joint.E = VelAccSolverUtils.velSolver(AngVel.BCE,E-C) + LinVel.Joint.C;
LinVel.Joint.F = VelAccSolverUtils.velSolver(AngVel.FG,F-G);
LinVel.Joint.G = [0 0 0];

% Determine the velocities at each link's center of mass
LinVel.LinkCoM.AB = VelAccSolverUtils.velSolver(AngVel.AB,AB_com - A);
LinVel.LinkCoM.BCE= VelAccSolverUtils.velSolver(AngVel.BCE,BCE_com - B) + LinVel.Joint.B;
LinVel.LinkCoM.CD= VelAccSolverUtils.velSolver(AngVel.CD,CD_com - D);
LinVel.LinkCoM.EF = VelAccSolverUtils.velSolver(AngVel.EF,EF_com - E) + LinVel.Joint.E;
LinVel.LinkCoM.FG = VelAccSolverUtils.velSolver(AngVel.FG,FG_com - G);

jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    Mechanism.LinVel.Joint.(jointNames{i}).(speedStr)(iter,:) = LinVel.Joint.(jointNames{i});
end
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.LinVel.LinkCoM.(linkNames{i}).(speedStr)(iter,:) = LinVel.LinkCoM.(linkNames{i});
end

end
function [Mechanism, AngAcc] = determineAngAcc(Mechanism, iter, speedStr, Pos, AngVel)
A = Pos.A;
B = Pos.B;
C = Pos.C;
D = Pos.D;
E = Pos.E;
F = Pos.F;
G = Pos.G;
%% Acceleration loops
%acceleration equations from given loops
syms aBCE aCD aEF aFG
alphaAB=[0 0 0];
alphaBCE=[0 0 aBCE];
alphaCD=[0 0 aCD];
alphaEF=[0 0 aEF];
alphaFG=[0 0 aFG];

% A->B->C->D->A
% A_ba + A_cb + A_dc + A_ad = 0
eqn1=VelAccSolverUtils.accSolver(AngVel.AB,alphaAB, B-A)+VelAccSolverUtils.accSolver(AngVel.BCE,alphaBCE,C-B)+VelAccSolverUtils.accSolver(AngVel.CD,alphaCD,D-C)==0;

% A->B->D->E->F->G->A
% A_ba + A_ba + A_db + A_ed + A_fe + A_gf + A_ag = 0
eqn2=VelAccSolverUtils.accSolver(AngVel.AB,alphaAB,B-A)+VelAccSolverUtils.accSolver(AngVel.BCE,alphaBCE,E-B)+VelAccSolverUtils.accSolver(AngVel.EF,alphaEF,F-E)+VelAccSolverUtils.accSolver(AngVel.FG,alphaFG,G-F)==0;

solution=solve([eqn1, eqn2],[aBCE aCD aEF aFG]);

% Store all the determined angular accelerations
AngAcc.AB=[0 0 0];
AngAcc.BCE=[0 0 double(solution.aBCE)]; %angular acceleration of BCE
AngAcc.CD=[0 0 double(solution.aCD)]; %angular acceleration of CD
AngAcc.EF=[0 0 double(solution.aEF)]; %angular acceleration of EF
AngAcc.FG=[0 0 double(solution.aFG)]; %angular acceleration of FG

linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.AngAcc.(linkNames{i}).(speedStr)(iter,:) = AngAcc.(linkNames{i});
end
end
function [Mechanism] = determineLinAcc(Mechanism, iter, speedStr, JointPos, LinkCoMPos, AngVel, AngAcc)
A = JointPos.A;
B = JointPos.B;
C = JointPos.C;
D = JointPos.D;
E = JointPos.E;
F = JointPos.F;
G = JointPos.G;

AB_com = LinkCoMPos.AB;
BCE_com = LinkCoMPos.BCE;
CD_com = LinkCoMPos.CD;
EF_com = LinkCoMPos.EF;
FG_com = LinkCoMPos.FG;

% Determine the accelerations at each joint
LinAcc.Joint.A = [0 0 0];
LinAcc.Joint.B = VelAccSolverUtils.accSolver(AngVel.AB, AngAcc.AB,B-A);
LinAcc.Joint.C = VelAccSolverUtils.accSolver(AngVel.CD, AngAcc.CD,C-D);
LinAcc.Joint.D = [0 0 0];
LinAcc.Joint.E = VelAccSolverUtils.accSolver(AngVel.BCE, AngAcc.BCE,E-B) + LinAcc.Joint.B;
LinAcc.Joint.F = VelAccSolverUtils.accSolver(AngVel.FG,AngAcc.FG, F-G);
LinAcc.Joint.G = [0 0 0];

% Determine the accelerations at each link's center of mass
LinAcc.LinkCoM.AB = VelAccSolverUtils.accSolver(AngVel.AB,AngAcc.AB,AB_com - A);
LinAcc.LinkCoM.BCE= VelAccSolverUtils.accSolver(AngVel.BCE,AngAcc.BCE,BCE_com - B) + LinAcc.Joint.B;
LinAcc.LinkCoM.CD= VelAccSolverUtils.accSolver(AngVel.CD,AngAcc.CD,CD_com - D);
LinAcc.LinkCoM.EF= VelAccSolverUtils.accSolver(AngVel.EF,AngAcc.EF,EF_com - E) + LinAcc.Joint.E;
LinAcc.LinkCoM.FG = VelAccSolverUtils.accSolver(AngVel.FG,AngAcc.FG,FG_com - G);

jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    Mechanism.LinAcc.Joint.(jointNames{i}).(speedStr)(iter,:) = LinAcc.Joint.(jointNames{i});
end
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.LinAcc.LinkCoM.(linkNames{i}).(speedStr)(iter,:) = LinAcc.LinkCoM.(linkNames{i});
end
end
