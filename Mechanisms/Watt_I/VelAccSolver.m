function Mechanism = VelAccSolver(Mechanism)
    Mechanism = VelAccSolverUtils.VelAccSolver(Mechanism, @determineAngVel, @determineLinVel, @determineAngAcc, @determineLinAcc);
end

%% Velocity loops
function [Mechanism, AngVel] = determineAngVel(Mechanism, iter, speedStr, JointPos, input_speed)
%velocity equations from given loops
syms wBCD wDE wEF wCFG
omegaAB=[0 0 input_speed];
omegaBCD=[0 0 wBCD];
omegaDE=[0 0 wDE];
omegaEF=[0 0 wEF];
omegaCFG=[0 0 wCFG];

A = JointPos.A;
B = JointPos.B;
C = JointPos.C;
D = JointPos.D;
E = JointPos.E;
F = JointPos.F;
G = JointPos.G;

% A->B->C->G->A
% V_ba + V_cb + V_gc + V_ag = 0
eqn1=VelAccSolverUtils.velSolver(omegaAB,B-A)+VelAccSolverUtils.velSolver(omegaBCD,C-B)+VelAccSolverUtils.velSolver(omegaCFG,G-C)==0;

% A->B->D->E->F->G->A
% V_ba + V_ba + V_db + V_ed + V_fe + V_gf + V_ag = 0
eqn2=VelAccSolverUtils.velSolver(omegaAB,B-A)+VelAccSolverUtils.velSolver(omegaBCD,D-B)+VelAccSolverUtils.velSolver(omegaDE,E-D)+VelAccSolverUtils.velSolver(omegaEF,F-E)+VelAccSolverUtils.velSolver(omegaCFG,G-F)==0;

solution=solve([eqn1, eqn2],[wBCD wDE wEF wCFG]);

% Store all the determined angular velocities
AngVel.AB=[0 0 input_speed];
AngVel.BCD=[0 0 double(solution.wBCD)]; %angular velocity of BCD
AngVel.DE=[0 0 double(solution.wDE)]; %angular velocity of DE
AngVel.EF=[0 0 double(solution.wEF)]; %angular velocity of EF
AngVel.CFG=[0 0 double(solution.wCFG)]; %angular velocity of CFG

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
BCD_com = LinkCoMPos.BCD;
DE_com = LinkCoMPos.DE;
EF_com = LinkCoMPos.EF;
CFG_com = LinkCoMPos.CFG;

LinVel.Joint.A = [0 0 0];
LinVel.Joint.B = VelAccSolverUtils.velSolver(AngVel.AB,B-A);
LinVel.Joint.C = VelAccSolverUtils.velSolver(AngVel.BCD,C-B) + LinVel.Joint.B;
LinVel.Joint.D = VelAccSolverUtils.velSolver(AngVel.BCD,D-B) + LinVel.Joint.B;
LinVel.Joint.E = VelAccSolverUtils.velSolver(AngVel.DE,E-D) + LinVel.Joint.D;
LinVel.Joint.F = VelAccSolverUtils.velSolver(AngVel.CFG,F-G);
LinVel.Joint.G = [0 0 0];

% Determine the velocities at each link's center of mass
LinVel.LinkCoM.AB = VelAccSolverUtils.velSolver(AngVel.AB,AB_com - A);
LinVel.LinkCoM.BCD= VelAccSolverUtils.velSolver(AngVel.BCD,BCD_com - B) + LinVel.Joint.B;
LinVel.LinkCoM.DE= VelAccSolverUtils.velSolver(AngVel.DE,DE_com - D) + LinVel.Joint.D;
LinVel.LinkCoM.EF = VelAccSolverUtils.velSolver(AngVel.EF,EF_com - E) + LinVel.Joint.E;
LinVel.LinkCoM.CFG = VelAccSolverUtils.velSolver(AngVel.CFG,CFG_com - G);

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
syms aBCD aDE aEF aCFG
alphaAB=[0 0 0];
alphaBCD=[0 0 aBCD];
alphaDE=[0 0 aDE];
alphaEF=[0 0 aEF];
alphaCFG=[0 0 aCFG];

% A->B->C->G->A
% A_ba + A_cb + A_gc + A_ag = 0
eqn1=VelAccSolverUtils.accSolver(AngVel.AB,alphaAB, B-A)+VelAccSolverUtils.accSolver(AngVel.BCD,alphaBCD,C-B)+VelAccSolverUtils.accSolver(AngVel.CFG,alphaCFG,G-C)==0;

% A->B->D->E->F->G->A
% A_ba + A_ba + A_db + A_ed + A_fe + A_gf + A_ag = 0
eqn2=VelAccSolverUtils.accSolver(AngVel.AB,alphaAB,B-A)+VelAccSolverUtils.accSolver(AngVel.BCD,alphaBCD,D-B)+VelAccSolverUtils.accSolver(AngVel.DE,alphaDE,E-D)+VelAccSolverUtils.accSolver(AngVel.EF,alphaEF,F-E)+VelAccSolverUtils.accSolver(AngVel.CFG,alphaCFG,G-F)==0;

solution=solve([eqn1, eqn2],[aBCD aDE aEF aCFG]);

% Store all the determined angular accelerations
AngAcc.AB=[0 0 0];
AngAcc.BCD=[0 0 double(solution.aBCD)]; %angular acceleration of BCE
AngAcc.DE=[0 0 double(solution.aDE)]; %angular acceleration of CD
AngAcc.EF=[0 0 double(solution.aEF)]; %angular acceleration of EF
AngAcc.CFG=[0 0 double(solution.aCFG)]; %angular acceleration of FG

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
BCD_com = LinkCoMPos.BCD;
DE_com = LinkCoMPos.DE;
EF_com = LinkCoMPos.EF;
CFG_com = LinkCoMPos.CFG;

% Determine the accelerations at each joint
LinAcc.Joint.A = [0 0 0];
LinAcc.Joint.B = VelAccSolverUtils.accSolver(AngVel.AB, AngAcc.AB,B-A);
LinAcc.Joint.C = VelAccSolverUtils.accSolver(AngVel.BCD, AngAcc.BCD,C-B) + LinAcc.Joint.B;
LinAcc.Joint.D = VelAccSolverUtils.accSolver(AngVel.BCD, AngAcc.BCD,D-B) + LinAcc.Joint.B;
LinAcc.Joint.E = VelAccSolverUtils.accSolver(AngVel.DE, AngAcc.DE,E-D) + LinAcc.Joint.D;
LinAcc.Joint.F = VelAccSolverUtils.accSolver(AngVel.CFG,AngAcc.CFG, F-G);
LinAcc.Joint.G = [0 0 0];

% Determine the accelerations at each link's center of mass
LinAcc.LinkCoM.AB = VelAccSolverUtils.accSolver(AngVel.AB,AngAcc.AB,AB_com - A);
LinAcc.LinkCoM.BCD= VelAccSolverUtils.accSolver(AngVel.BCD,AngAcc.BCD,BCD_com - B) + LinAcc.Joint.B;
LinAcc.LinkCoM.DE= VelAccSolverUtils.accSolver(AngVel.DE,AngAcc.DE,DE_com - D) + LinAcc.Joint.D;
LinAcc.LinkCoM.EF= VelAccSolverUtils.accSolver(AngVel.EF,AngAcc.EF,EF_com - E) + LinAcc.Joint.E;
LinAcc.LinkCoM.CFG = VelAccSolverUtils.accSolver(AngVel.CFG,AngAcc.CFG,CFG_com - G);

jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    Mechanism.LinAcc.Joint.(jointNames{i}).(speedStr)(iter,:) = LinAcc.Joint.(jointNames{i});
end
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.LinAcc.LinkCoM.(linkNames{i}).(speedStr)(iter,:) = LinAcc.LinkCoM.(linkNames{i});
end
end
