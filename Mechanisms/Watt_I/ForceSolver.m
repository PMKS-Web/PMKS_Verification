function Mechanism = ForceSolver(Mechanism, scenarios)
    Mechanism = ForceSolverUtils.ForceSolver(Mechanism, scenarios, @performForceAnalysis);
end

function solution = performForceAnalysis(Mechanism, iter, speedStr, JointPos, LinkCoMPos, newton, grav, friction)
% Here, you'd implement your equations based on static conditions
% For each joint and link, calculate forces and moments ensuring sum of forces = 0 and sum of moments = 0

massAB = Mechanism.Mass.AB;
massBCD = Mechanism.Mass.BCD;
massDE = Mechanism.Mass.DE;
massEF = Mechanism.Mass.EF;
massCFG = Mechanism.Mass.CFG;

massMoIAB = Mechanism.MassMoI.AB;
massMoIBCD = Mechanism.MassMoI.BCD;
massMoIDE = Mechanism.MassMoI.DE;
massMoIEF = Mechanism.MassMoI.EF;
massMoICFG = Mechanism.MassMoI.CFG;

A_ab = Mechanism.AngAcc.AB.(speedStr)(iter,:);
A_bcd = Mechanism.AngAcc.BCD.(speedStr)(iter,:);
A_de = Mechanism.AngAcc.DE.(speedStr)(iter,:);
A_ef = Mechanism.AngAcc.EF.(speedStr)(iter,:);
A_cfg = Mechanism.AngAcc.CFG.(speedStr)(iter,:);

A_ab_com = Mechanism.LinAcc.LinkCoM.AB.(speedStr)(iter,:);
A_bcd_com = Mechanism.LinAcc.LinkCoM.BCD.(speedStr)(iter,:);
A_de_com = Mechanism.LinAcc.LinkCoM.DE.(speedStr)(iter,:);
A_ef_com = Mechanism.LinAcc.LinkCoM.EF.(speedStr)(iter,:);
A_cfg_com = Mechanism.LinAcc.LinkCoM.CFG.(speedStr)(iter,:);

% This is a placeholder for the actual static analysis logic
% You'll need to adapt this to your specific requirements
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

syms Ax Ay Bx By Cx Cy Dx Dy Ex Ey Fx Fy Gx Gy T

g = [0 -9.81 0]; %defining gravity to find weight of each link m/s^2

% Forces at each joint
fA=[Ax Ay 0];
fB=[Bx By 0];
fC=[Cx Cy 0];
fD=[Dx Dy 0];
fE=[Ex Ey 0];
fF=[Fx Fy 0];
fG=[Gx Gy 0];

% Weight of each link
wAB=massAB *g * grav;
wBCD=massBCD *g * grav;
wDE=massDE *g * grav;
wEF=massEF *g * grav;
wCFG=massCFG *g * grav;

% Unknown torque of the system
tT=[0 0 T];

% Force of the applied load
LoadForce=[50 25 0];
LoadPos = (C + F + G) / 3;

%% Static Equilibrium Equations
%Link AB
eqn1=fA+fB+wAB==massAB*A_ab_com * newton;
eqn2=ForceSolverUtils.momentVec(A, AB_com, fA) + ForceSolverUtils.momentVec(B,  AB_com,fB)+tT==massMoIAB * A_ab * newton; %only change the ==0 appropriately for newtons 2nd law
%Link BCD
eqn3=-fB+fC+fD+wBCD==massBCD*A_bcd_com * newton;
eqn4=ForceSolverUtils.momentVec(B, BCD_com, -fB)+ForceSolverUtils.momentVec(C, BCD_com, fC) + ForceSolverUtils.momentVec(D, BCD_com, fD) ==massMoIBCD * A_bcd * newton; %only change the ==0 appropriately for newtons 2nd law
%Link DE
eqn5=-fD+fE+wDE==massDE*A_de_com * newton;
eqn6=ForceSolverUtils.momentVec(D, DE_com, -fD)+ForceSolverUtils.momentVec(E, DE_com, fE)==massMoIDE * A_de * newton; %only change the ==0 appropriately for newtons 2nd law
%Link EF
eqn7=-fE+fF+wEF==massEF*A_ef_com * newton;
eqn8=ForceSolverUtils.momentVec(E, EF_com, -fE)+ForceSolverUtils.momentVec(F, EF_com, fF)==massMoIEF * A_ef * newton; %only change the ==0 appropriately for newtons 2nd law
%Link CFG
eqn9=-fC-fF+fG+wCFG+LoadForce==massCFG*A_cfg_com * newton;
eqn10=ForceSolverUtils.momentVec(C, CFG_com, -fC)+ForceSolverUtils.momentVec(F, CFG_com, -fF)+ForceSolverUtils.momentVec(G, CFG_com, fG)+ForceSolverUtils.momentVec(LoadPos, CFG_com, LoadForce)==massMoICFG * A_cfg * newton; %only change the ==0 appropriately for newtons 2nd law

solution = (solve([eqn1,eqn2,eqn3,eqn4,eqn5,eqn6,eqn7,eqn8,eqn9,eqn10],[Ax,Ay,Bx,By,Cx,Cy,Dx,Dy,Ex,Ey,Fx,Fy,Gx,Gy,T]));
end
