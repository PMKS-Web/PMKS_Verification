function Mechanism = PosSolver(Mechanism, input_speed)
    Mechanism = PosSolverUtils.PosSolver(Mechanism, input_speed, @calculateDistances, @calculateNewPositions);
end

% Function to calculate distances between joints
function Mechanism = calculateDistances(Mechanism)
% Points
A = Mechanism.Joint.A;
B = Mechanism.Joint.B;
C = Mechanism.Joint.C;
D = Mechanism.Joint.D;
E = Mechanism.TracerPoint.E;
F = Mechanism.TracerPoint.F;
G = Mechanism.TracerPoint.G;
H = Mechanism.TracerPoint.H;
% Distance Between Points
% Link ABE
Mechanism.LinkLength.AB = norm(A - B);
Mechanism.LinkLength.AE = norm(A - E);
Mechanism.LinkLength.BE = norm(B - E);
% Link BCFG
Mechanism.LinkLength.BC = norm(B - C);
Mechanism.LinkLength.BF = norm(B - F);
Mechanism.LinkLength.BG = norm(B - G);
Mechanism.LinkLength.CF = norm(C - F);
Mechanism.LinkLength.CG = norm(C - G);
Mechanism.LinkLength.FG = norm(F - G);
% Link CDH
Mechanism.LinkLength.CD = norm(C - D);
Mechanism.LinkLength.CH = norm(C - H);
Mechanism.LinkLength.DH = norm(D - H);
% Link ABE CoM with Joint A
Mechanism.LinkLength.ABE_CoM_A = norm(Mechanism.LinkCoM.ABE(1,:)- A);
Mechanism.LinkLength.ABE_CoM_B = norm(Mechanism.LinkCoM.ABE(1,:)- B);
% Link BCFG CoM with Joint B
Mechanism.LinkLength.BCFG_CoM_B = norm(Mechanism.LinkCoM.BCFG(1,:) - B);
Mechanism.LinkLength.BCFG_CoM_C = norm(Mechanism.LinkCoM.BCFG(1,:) - C);
% Link CDH CoM with Joint C
Mechanism.LinkLength.CDH_CoM_C = norm(Mechanism.LinkCoM.CDH(1,:) - C);
Mechanism.LinkLength.CDH_CoM_D = norm(Mechanism.LinkCoM.CDH(1,:) - D);
end

% Function to calculate new positions for the joints
function [Mechanism, valid, theta, iteration] = calculateNewPositions(Mechanism, theta, iteration, forwardDir)
% Initialize validity flag
valid = true;

A = Mechanism.Joint.A(1, :);
D = Mechanism.Joint.D(1, :);

% Direct calculation for B
B = [A(1) + Mechanism.LinkLength.AB * cos(theta), A(2) + Mechanism.LinkLength.AB * sin(theta), 0];

% Circle-circle intersections for C, E, F, G
C = PosSolverUtils.circleCircleIntersection(B(1), B(2), Mechanism.LinkLength.BC, D(1), D(2), Mechanism.LinkLength.CD, Mechanism.Joint.C(iteration - 1, 1), Mechanism.Joint.C(iteration - 1, 2));
if isempty(C), valid = false; return; end
% E = PosSolverUtils.circleCircleIntersection(A(1), A(2), Mechanism.LinkLength.AE, B(1), B(2), Mechanism.LinkLength.BE, Mechanism.TracerPoint.E(iteration - 1, 1), Mechanism.TracerPoint.E(iteration - 1, 2));
% if isempty(E), valid = false; return; end
% F = PosSolverUtils.circleCircleIntersection(B(1), B(2), Mechanism.LinkLength.BF, C(1), C(2), Mechanism.LinkLength.CF, Mechanism.TracerPoint.F(iteration - 1, 1), Mechanism.TracerPoint.F(iteration - 1, 2));
% if isempty(F), valid = false; return; end
% G = PosSolverUtils.circleCircleIntersection(B(1), B(2), Mechanism.LinkLength.BG, C(1), C(2), Mechanism.LinkLength.CG, Mechanism.TracerPoint.G(iteration - 1, 1), Mechanism.TracerPoint.G(iteration - 1, 2));
% if isempty(G), valid = false; return; end
% H = PosSolverUtils.circleCircleIntersection(C(1), C(2), Mechanism.LinkLength.CH, D(1), D(2), Mechanism.LinkLength.DH, Mechanism.TracerPoint.H(iteration - 1, 1), Mechanism.TracerPoint.H(iteration - 1, 2));
% if isempty(H), valid = false; return; end
E_index = PosSolverUtils.determineIntersectionIndex(Mechanism.Joint.A(1, 1), Mechanism.Joint.A(1, 2), Mechanism.LinkLength.AE, Mechanism.Joint.B(1, 1), Mechanism.Joint.B(1, 2), Mechanism.LinkLength.BE, Mechanism.TracerPoint.E(iteration - 1, 1), Mechanism.TracerPoint.E(iteration - 1, 2));
E = PosSolverUtils.determineTracerPoint(A(1, 1), A(2), Mechanism.LinkLength.AE, B(1), B(2), Mechanism.LinkLength.BE, Mechanism.TracerPoint.E(iteration - 1, 1), Mechanism.TracerPoint.E(iteration - 1, 2), E_index);
if isempty(E), valid = false; return; end

F_index = PosSolverUtils.determineIntersectionIndex(Mechanism.Joint.B(1, 1), Mechanism.Joint.B(1, 2), Mechanism.LinkLength.BF, Mechanism.Joint.C(1, 1), Mechanism.Joint.C(1, 2), Mechanism.LinkLength.CF, Mechanism.TracerPoint.F(iteration - 1, 1), Mechanism.TracerPoint.F(iteration - 1, 2));
F = PosSolverUtils.determineTracerPoint(B(1), B(2), Mechanism.LinkLength.BF, C(1), C(2), Mechanism.LinkLength.CF, Mechanism.TracerPoint.F(iteration - 1, 1), Mechanism.TracerPoint.F(iteration - 1, 2), F_index);
if isempty(F), valid = false; return; end

G_index = PosSolverUtils.determineIntersectionIndex(Mechanism.Joint.B(1, 1), Mechanism.Joint.B(1, 2), Mechanism.LinkLength.BG, Mechanism.Joint.C(1, 1), Mechanism.Joint.C(1, 2), Mechanism.LinkLength.CG, Mechanism.TracerPoint.G(iteration - 1, 1), Mechanism.TracerPoint.G(iteration - 1, 2));
G = PosSolverUtils.determineTracerPoint(B(1), B(2), Mechanism.LinkLength.BG, C(1), C(2), Mechanism.LinkLength.CG, Mechanism.TracerPoint.G(iteration - 1, 1), Mechanism.TracerPoint.G(iteration - 1, 2), G_index);
if isempty(G), valid = false; return; end

H_index = PosSolverUtils.determineIntersectionIndex(Mechanism.Joint.C(1, 1), Mechanism.Joint.C(1, 2), Mechanism.LinkLength.CH, Mechanism.Joint.D(1, 1), Mechanism.Joint.D(1, 2), Mechanism.LinkLength.DH, Mechanism.TracerPoint.H(iteration - 1, 1), Mechanism.TracerPoint.H(iteration - 1, 2));
H = PosSolverUtils.determineTracerPoint(C(1), C(2), Mechanism.LinkLength.CH, D(1), D(2), Mechanism.LinkLength.DH, Mechanism.TracerPoint.H(iteration - 1, 1), Mechanism.TracerPoint.H(iteration - 1, 2), H_index);
if isempty(H), valid = false; return; end

% Update positions
Mechanism.Joint.A(iteration, :) = A;
Mechanism.Joint.B(iteration, :) = B;
Mechanism.Joint.C(iteration, :) = C;
Mechanism.Joint.D(iteration, :) = D;
Mechanism.TracerPoint.E(iteration, :) = E;
Mechanism.TracerPoint.F(iteration, :) = F;
Mechanism.TracerPoint.G(iteration, :) = G;
Mechanism.TracerPoint.H(iteration, :) = H;

utilsFolderPath = fullfile(pwd);
addpath(utilsFolderPath);

Mechanism.LinkCoM.ABE(iteration, :) = PosSolverUtils.circleCircleIntersection(A(1), A(2), Mechanism.LinkLength.ABE_CoM_A, B(1), B(2), Mechanism.LinkLength.ABE_CoM_B, Mechanism.LinkCoM.ABE(iteration - 1, 1), Mechanism.LinkCoM.ABE(iteration - 1, 2));
Mechanism.LinkCoM.BCFG(iteration, :) = PosSolverUtils.circleCircleIntersection(B(1), B(2), Mechanism.LinkLength.BCFG_CoM_B, C(1), C(2), Mechanism.LinkLength.BCFG_CoM_C, Mechanism.LinkCoM.BCFG(iteration - 1, 1), Mechanism.LinkCoM.BCFG(iteration - 1, 2));
Mechanism.LinkCoM.CDH(iteration, :) = PosSolverUtils.circleCircleIntersection(C(1), C(2), Mechanism.LinkLength.CDH_CoM_C, D(1), D(2), Mechanism.LinkLength.CDH_CoM_D, Mechanism.LinkCoM.CDH(iteration - 1, 1), Mechanism.LinkCoM.CDH(iteration - 1, 2));

% Define angles for each sensor
Mechanism.Angle.Joint.E(iteration, :) = [0 0 rad2deg(atan2(E(2) - A(2), E(1) - A(1)))];
Mechanism.Angle.Joint.F(iteration, :) = [0 0 rad2deg(atan2(F(2) - B(2), F(1) - B(1)))];
Mechanism.Angle.Joint.G(iteration, :) = [0 0 rad2deg(atan2(G(2) - B(2), G(1) - B(1)))];
Mechanism.Angle.Joint.H(iteration, :) = [0 0 rad2deg(atan2(H(2) - D(2), H(1) - D(1)))];

for inputSpeedCol = 1:1:length(Mechanism.inputSpeed(1,:))
    if (forwardDir)
        Mechanism.inputSpeed(iteration, inputSpeedCol) = Mechanism.inputSpeed(1, inputSpeedCol);
    else
        Mechanism.inputSpeed(iteration, inputSpeedCol) = Mechanism.inputSpeed(1, inputSpeedCol) * -1;
    end
end

% if (forwardDir)
%     Mechanism.inputSpeed(iteration) = Mechanism.inputSpeed(1);
% else
%     Mechanism.inputSpeed(iteration) = Mechanism.inputSpeed(1) * -1;
% end
iteration = iteration + 1;
end