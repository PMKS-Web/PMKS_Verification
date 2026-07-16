function Mechanism = ForceSolver(Mechanism, scenarios)
    Mechanism = ForceSolverUtils.ForceSolver(Mechanism, scenarios, @performForceAnalysis);
end

function solution = performForceAnalysis(Mechanism, iter, speedStr, JointPos, LinkCoMPos, newton, grav, friction)
% Here, you'd implement your equations based on static conditions
% For each joint and link, calculate forces and moments ensuring sum of forces = 0 and sum of moments = 0

massAB = Mechanism.Mass.AB;
massBCE = Mechanism.Mass.BCE;
massCD = Mechanism.Mass.CD;
massEF = Mechanism.Mass.EF;
massFG = Mechanism.Mass.FG;

massMoIAB = Mechanism.MassMoI.AB;
massMoIBCE = Mechanism.MassMoI.BCE;
massMoICD = Mechanism.MassMoI.CD;
massMoIEF = Mechanism.MassMoI.EF;
massMoIFG = Mechanism.MassMoI.FG;

A_ab = Mechanism.AngAcc.AB.(speedStr)(iter,:);
A_bce = Mechanism.AngAcc.BCE.(speedStr)(iter,:);
A_cd = Mechanism.AngAcc.CD.(speedStr)(iter,:);
A_ef = Mechanism.AngAcc.EF.(speedStr)(iter,:);
A_fg = Mechanism.AngAcc.FG.(speedStr)(iter,:);

A_ab_com = Mechanism.LinAcc.LinkCoM.AB.(speedStr)(iter,:);
A_bce_com = Mechanism.LinAcc.LinkCoM.BCE.(speedStr)(iter,:);
A_cd_com = Mechanism.LinAcc.LinkCoM.CD.(speedStr)(iter,:);
A_ef_com = Mechanism.LinAcc.LinkCoM.EF.(speedStr)(iter,:);
A_fg_com = Mechanism.LinAcc.LinkCoM.FG.(speedStr)(iter,:);

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
BCE_com = LinkCoMPos.BCE;
CD_com = LinkCoMPos.CD;
EF_com = LinkCoMPos.EF;
FG_com = LinkCoMPos.FG;

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
wBCE=massBCE *g * grav;
wCD=massCD *g * grav;
wEF=massEF *g * grav;
wFG=massFG *g * grav;

% Unknown torque of the system
tT=[0 0 T];

% Force of the applied load
LoadForce=[50 0 0];
LoadPos = (F + G) / 2;

%% Static Equilibrium Equations
%Link AB
eqn1=fA+fB+wAB==massAB*A_ab_com * newton;
eqn2=ForceSolverUtils.momentVec(A, AB_com, fA) + ForceSolverUtils.momentVec(B,  AB_com,fB)+tT==massMoIAB * A_ab * newton; %only change the ==0 appropriately for newtons 2nd law
%Link BCE
eqn3=-fB+fC+fE+wBCE==massBCE*A_bce_com * newton;
eqn4=ForceSolverUtils.momentVec(B, BCE_com, -fB)+ForceSolverUtils.momentVec(C, BCE_com, fC) + ForceSolverUtils.momentVec(E, BCE_com, fE) ==massMoIBCE * A_bce * newton; %only change the ==0 appropriately for newtons 2nd law
%Link CD
eqn5=-fC+fD+wCD==massCD*A_cd_com * newton;
eqn6=ForceSolverUtils.momentVec(C, CD_com, -fC)+ForceSolverUtils.momentVec(D, CD_com, fD)==massMoICD * A_cd * newton; %only change the ==0 appropriately for newtons 2nd law
%Link EF
eqn7=-fE+fF+wEF==massEF*A_ef_com * newton;
eqn8=ForceSolverUtils.momentVec(E, EF_com, -fE)+ForceSolverUtils.momentVec(F, EF_com, fF)==massMoIEF * A_ef * newton; %only change the ==0 appropriately for newtons 2nd law
%Link FG
eqn9=-fF+fG+wFG+LoadForce==massFG*A_fg_com * newton;
eqn10=ForceSolverUtils.momentVec(F, FG_com, -fF)+ForceSolverUtils.momentVec(G, FG_com, fG)+ForceSolverUtils.momentVec(LoadPos, FG_com, LoadForce)==massMoIFG * A_fg * newton; %only change the ==0 appropriately for newtons 2nd law

solution = (solve([eqn1,eqn2,eqn3,eqn4,eqn5,eqn6,eqn7,eqn8,eqn9,eqn10],[Ax,Ay,Bx,By,Cx,Cy,Dx,Dy,Ex,Ey,Fx,Fy,Gx,Gy,T]));
end
