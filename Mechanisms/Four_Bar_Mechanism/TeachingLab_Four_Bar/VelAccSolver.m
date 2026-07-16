function Mechanism = VelAccSolver(Mechanism)
    Mechanism = VelAccSolverUtils.VelAccSolver(Mechanism, @determineAngVel, @determineLinVel, @determineAngAcc, @determineLinAcc);
end

%% Velocity loops
function [Mechanism, AngVel] = determineAngVel(Mechanism, iter, speedStr, JointPos, input_speed)

% velocity equations from given loops
syms wBCFG wCDEI 
omegaABH=[0 0 input_speed];
omegaBCFG=[0 0 wBCFG];
omegaCDEI=[0 0 wCDEI];

A = JointPos.A;
B = JointPos.B;
C = JointPos.C;
D = JointPos.D;

% A->B->C->D->A
% V_ba + V_cb + V_dc + V_ad = 0
eqn1=VelAccSolverUtils.velSolver(omegaABH,B-A)+VelAccSolverUtils.velSolver(omegaBCFG,C-B)+VelAccSolverUtils.velSolver(omegaCDEI,D-C)==0;

solution=solve(eqn1,[wBCFG wCDEI]);

% Store all the determined angular velocities
AngVel.ABH=[0 0 input_speed];
AngVel.BCFG=[0 0 double(solution.wBCFG)]; %angular velocity of BCFG
AngVel.CDEI=[0 0 double(solution.wCDEI)]; %angular velocity of DE

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
H = JointPos.H;
I = JointPos.I;

ABH_com = LinkCoMPos.ABH;
BCFG_com = LinkCoMPos.BCFG;
CDEI_com = LinkCoMPos.CDEI;

LinVel.Joint.A = [0 0 0];
LinVel.Joint.B = VelAccSolverUtils.velSolver(AngVel.ABH,B-A);
LinVel.Joint.C = VelAccSolverUtils.velSolver(AngVel.CDEI,C-D);
LinVel.Joint.D = [0 0 0];
LinVel.Joint.E = VelAccSolverUtils.velSolver(AngVel.CDEI,E-D);
LinVel.Joint.F = VelAccSolverUtils.velSolver(AngVel.BCFG,F-C) + LinVel.Joint.C;
LinVel.Joint.G = VelAccSolverUtils.velSolver(AngVel.BCFG, G-C) + LinVel.Joint.C;
LinVel.Joint.H = VelAccSolverUtils.velSolver(AngVel.ABH, H-A);
LinVel.Joint.I = VelAccSolverUtils.velSolver(AngVel.CDEI, I-D);

% Determine the velocities at each link's center of mass
LinVel.LinkCoM.ABH = VelAccSolverUtils.velSolver(AngVel.ABH,ABH_com - A);
LinVel.LinkCoM.BCFG= VelAccSolverUtils.velSolver(AngVel.BCFG,BCFG_com - B) + LinVel.Joint.B;
LinVel.LinkCoM.CDEI= VelAccSolverUtils.velSolver(AngVel.CDEI,CDEI_com - D);

jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    Mechanism.LinVel.Joint.(jointNames{i}).(speedStr)(iter,:) = LinVel.Joint.(jointNames{i});
end
tracerPointNames = fieldnames(Mechanism.TracerPoint);
for i = 1:length(tracerPointNames)
    Mechanism.LinVel.Joint.(tracerPointNames{i}).(speedStr)(iter,:) = LinVel.Joint.(tracerPointNames{i});
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

%% Acceleration loops
%acceleration equations from given loops
syms aBCFG aCDEI
alphaABH=[0 0 0];
alphaBCFG=[0 0 aBCFG];
alphaCDEI=[0 0 aCDEI];

% A->B->C->D->A
% A_ba + A_cb + A_dc + A_ad = 0
eqn1=VelAccSolverUtils.accSolver(AngVel.ABH,alphaABH, B-A)+VelAccSolverUtils.accSolver(AngVel.BCFG,alphaBCFG,C-B)+VelAccSolverUtils.accSolver(AngVel.CDEI,alphaCDEI,D-C)==0;

solution=solve(eqn1,[aBCFG aCDEI]);

% Store all the determined angular accelerations
AngAcc.ABH=[0 0 0];
AngAcc.BCFG=[0 0 double(solution.aBCFG)]; %angular acceleration of BCFG
AngAcc.CDEI=[0 0 double(solution.aCDEI)]; %angular acceleration of CDEI

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
H = JointPos.H;
I = JointPos.I;

ABH_com = LinkCoMPos.ABH;
BCFG_com = LinkCoMPos.BCFG;
CDEI_com = LinkCoMPos.CDEI;

% Determine the accelerations at each joint
LinAcc.Joint.A = [0 0 0];
LinAcc.Joint.B = VelAccSolverUtils.accSolver(AngVel.ABH, AngAcc.ABH,B-A);
LinAcc.Joint.C = VelAccSolverUtils.accSolver(AngVel.CDEI, AngAcc.CDEI,C-D);
LinAcc.Joint.D = [0 0 0];
LinAcc.Joint.E = VelAccSolverUtils.accSolver(AngVel.CDEI, AngAcc.CDEI,E-D);
LinAcc.Joint.F = VelAccSolverUtils.accSolver(AngVel.BCFG, AngAcc.BCFG,F-C) + LinAcc.Joint.C;
LinAcc.Joint.G = VelAccSolverUtils.accSolver(AngVel.BCFG, AngAcc.BCFG,G-C) + LinAcc.Joint.C;
LinAcc.Joint.H = VelAccSolverUtils.accSolver(AngVel.ABH, AngAcc.ABH,H-A);
LinAcc.Joint.I = VelAccSolverUtils.accSolver(AngVel.CDEI, AngAcc.CDEI,I-D);

% Determine the accelerations at each link's center of mass
LinAcc.LinkCoM.ABH = VelAccSolverUtils.accSolver(AngVel.ABH,AngAcc.ABH,ABH_com - A);
LinAcc.LinkCoM.BCFG= VelAccSolverUtils.accSolver(AngVel.BCFG,AngAcc.BCFG,BCFG_com - B) + LinAcc.Joint.B;
LinAcc.LinkCoM.CDEI= VelAccSolverUtils.accSolver(AngVel.CDEI,AngAcc.CDEI,CDEI_com - D);

jointNames = fieldnames(Mechanism.Joint);
for i = 1:length(jointNames)
    Mechanism.LinAcc.Joint.(jointNames{i}).(speedStr)(iter,:) = LinAcc.Joint.(jointNames{i});
end
tracerPointNames = fieldnames(Mechanism.TracerPoint);
for i = 1:length(tracerPointNames)
    Mechanism.LinAcc.Joint.(tracerPointNames{i}).(speedStr)(iter,:) = LinAcc.Joint.(tracerPointNames{i});
end
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:length(linkNames)
    Mechanism.LinAcc.LinkCoM.(linkNames{i}).(speedStr)(iter,:) = LinAcc.LinkCoM.(linkNames{i});
end
end
