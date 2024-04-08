function Mechanism = ForceSolver(Mechanism, scenarios)
    Mechanism = ForceSolverUtils.ForceSolver(Mechanism, scenarios, @performForceAnalysis);
end

function solution = performForceAnalysis(Mechanism, iter, JointPos, LinkCoMPos, newton, grav, friction)
% Pull the mass of each component
massAB = Mechanism.Mass.AB;
massBC = Mechanism.Mass.BC;
massPiston = Mechanism.Mass.Piston;

% Pull the mass moment of inertia of each component
massMoIAB = Mechanism.MassMoI.AB;
massMoIBC = Mechanism.MassMoI.BC;

% Pull the angular acceleration of each link
A_ab = Mechanism.AngAcc.AB(iter,:);
A_bc = Mechanism.AngAcc.BC(iter,:);

% Pull the acceleration of each link at its center of mass
A_ab_com = Mechanism.LinAcc.LinkCoM.AB(iter,:);
A_bc_com = Mechanism.LinAcc.LinkCoM.BC(iter,:);
A_piston = Mechanism.LinAcc.Joint.C(iter,:);

% Extract positions for each joint
A = JointPos.A;
B = JointPos.B;
C = JointPos.C;

% Extract positions for each link's center of mass
AB_com = LinkCoMPos.AB;
BC_com = LinkCoMPos.BC;

% Extract the angle that the slider travels on
theta = Mechanism.Theta;

% Define all the unknown variables to solve for
syms Ax Ay Bx By Cx Cy N T

%defining gravity to find weight of each link m/s^2
g = [0 -9.81 0];

% Forces at each joint
fA=[Ax Ay 0];
fB=[Bx By 0];
fC=[Cx Cy 0];

% Weight of each link
wAB=massAB*g*grav;
wBC=massBC*g*grav;
wPiston = massPiston*g*grav;

% Unknown torque of the system
tT=[0 0 T];

mu = 0.34; % Coefficient of friction

% Normal Force
% F_N = [N*cos(theta), N*sin(theta), 0];
% Determine the direction of the friction force at the slider-cylinder interface
if Mechanism.LinVel.Joint.C(iter,1) > 0
    % F_fr = [mu*F_N*-1, 0]; % Assuming horizontal motion
    F_fr =[-mu*N,N,0];
elseif Mechanism.LinVel.Joint.C(iter,1) < 0
    F_fr =[mu*N,N,0];
    % F_fr = [0, mu * F_N * 1, 0];
else
    F_fr =[-mu*N*0,N,0];
    % F_fr = [0, mu * F_N * 0, 0];
end


% Torque provided by friction on Joint A
r_ab_com_a = norm(AB_com - A);
r_bc_com_b = norm(BC_com - B);

A_noFriction_x = Mechanism.NewtonForceGravNoFriction.Joint.A(iter,1);
A_noFriction_y = Mechanism.NewtonForceGravNoFriction.Joint.A(iter,2);
B_noFriction_x = Mechanism.NewtonForceGravNoFriction.Joint.B(iter,1); 
B_noFriction_y = Mechanism.NewtonForceGravNoFriction.Joint.B(iter,2);

% Correcting angle calculation
A_theta = atan2(A_noFriction_y, A_noFriction_x);
B_theta = atan2(B_noFriction_y, B_noFriction_x);

A_friction_Mag = norm([A_noFriction_x, A_noFriction_y]);
B_friction_Mag = norm([B_noFriction_x, A_noFriction_y]);

% Correct normal force direction
F_normal_A = [A_friction_Mag*cos(A_theta), A_friction_Mag*sin(A_theta), 0];
F_normal_B = [B_friction_Mag*cos(B_theta), B_friction_Mag*sin(B_theta), 0];

% Calculate friction forces based on estimated normal forces, conditionally
if friction == 1
F_friction_A = mu * norm(F_normal_A) * [-sin(A_theta), cos(A_theta), 0]; % Perpendicular to normal force
F_friction_B = mu * norm(F_normal_B) * [-sin(B_theta), cos(B_theta), 0]; % Perpendicular to normal force
else
F_friction_A = [0 0 0]; % Perpendicular to normal force
F_friction_B = [0 0 0]; % Perpendicular to normal force
end

% Calculate torques due to friction conditionally
if friction == 1
T_fr_A = [0,0, mu * norm(F_normal_A) * r_ab_com_a]; % Torque due to friction at A
T_fr_B = [0,0, mu * norm(F_normal_B) * r_bc_com_b]; % Torque due to friction at B
else
T_fr_A = [0,0,0]; % Torque due to friction at A
T_fr_B = [0,0,0]; % Torque due to friction at B
end

%% FBD Equations
%Link AB
eqn1=fA+fB+wAB+F_friction_A+F_friction_B==massAB*A_ab_com*newton;
eqn2=ForceSolverUtils.momentVec(A, AB_com, fA) + ForceSolverUtils.momentVec(B,  AB_com,fB)+tT+T_fr_A+T_fr_B==massMoIAB * A_ab*newton; %only change the ==0 appropriately for newtons 2nd law
% eqn2=ForceSolverUtils.momentVec(A, AB_com, fA) + ForceSolverUtils.momentVec(B,  AB_com,fB)+T_fb+tT==massMoIAB * A_ab*newton; %only change the ==0 appropriately for newtons 2nd law
%Link BC
eqn3=-fB+fC+wBC-F_friction_B==massBC*A_bc_com*newton;
eqn4=ForceSolverUtils.momentVec(B, BC_com, -fB)+ForceSolverUtils.momentVec(C, BC_com, fC)-T_fr_B==massMoIBC * A_bc*newton; %only change the ==0 appropriately for newtons 2nd law
% eqn4=ForceSolverUtils.momentVec(B, BC_com, -fB)+ForceSolverUtils.momentVec(C, BC_com, fC)-T_fb==massMoIBC * A_bc*newton; %only change the ==0 appropriately for newtons 2nd law
% Piston
eqn5=-fC+F_fr+wPiston==massPiston*A_piston*newton;

solution = (solve([eqn1,eqn2,eqn3,eqn4,eqn5],[Ax,Ay,Bx,By,Cx,Cy,N,T]));
end