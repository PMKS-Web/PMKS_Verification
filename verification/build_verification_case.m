function Mechanism = build_verification_case(caseName, config)
%BUILD_VERIFICATION_CASE Build a case without experimental files or saved state.

switch char(caseName)
    case 'watt_i'
        Mechanism = buildWattI();
    case 'stephenson_iii_example_2'
        Mechanism = buildStephensonIIIExample2();
    case 'teaching_four_bar'
        Mechanism = buildTeachingFourBar();
    case 'teaching_slider_crank'
        Mechanism = buildTeachingSliderCrank();
    case 'slider_crank_tracer'
        Mechanism = buildSliderCrankTracer();
    otherwise
        error('Verification:UnknownCase', 'Unknown verification case: %s', caseName);
end

Mechanism.input_speed_str = config.speedRpm;
end

function Mechanism = buildWattI()
A = [-3.74, -2.41, 0];
B = [-2.72, 0.91, 0];
C = [1.58, 0.43, 0];
D = [-0.24, 4.01, 0];
E = [5.08, 5.31, 0];
F = [8.14, 3.35, 0];
G = [7.32, -3.51, 0];

Mechanism = baseMechanism(struct('A', A, 'B', B, 'C', C, 'D', D, 'E', E, 'F', F, 'G', G));
Mechanism.LinkCoM.AB = GeneralUtils.determineCoM([A; B]);
Mechanism.LinkCoM.BCD = GeneralUtils.determineCoM([B; C; D]);
Mechanism.LinkCoM.DE = GeneralUtils.determineCoM([D; E]);
Mechanism.LinkCoM.EF = GeneralUtils.determineCoM([E; F]);
Mechanism.LinkCoM.CFG = GeneralUtils.determineCoM([C; F; G]);
Mechanism.Mass = struct('AB', 5, 'BCD', 10, 'DE', 5, 'EF', 10, 'CFG', 5);
Mechanism.MassMoI = struct('AB', 0.1, 'BCD', 0.2, 'DE', 0.1, 'EF', 0.2, 'CFG', 0.1);
Mechanism = addLinkAngles(Mechanism, struct('AB', 'A', 'BCD', 'B', 'DE', 'D', 'EF', 'E', 'CFG', 'G'));
end

function Mechanism = buildStephensonIIIExample2()
A = [7, 4, 0];
B = [5, 16, 0];
C = [25, 25, 0];
D = [23, 10, 0];
E = [18, 35, 0];
F = [43, 32, 0];
G = [45, 17, 0];

Mechanism = baseMechanism(struct('A', A, 'B', B, 'C', C, 'D', D, 'E', E, 'F', F, 'G', G));
Mechanism.LinkCoM.AB = GeneralUtils.determineCoM([A; B]);
Mechanism.LinkCoM.BCE = GeneralUtils.determineCoM([B; C; E]);
Mechanism.LinkCoM.CD = GeneralUtils.determineCoM([C; D]);
Mechanism.LinkCoM.EF = GeneralUtils.determineCoM([E; F]);
Mechanism.LinkCoM.FG = GeneralUtils.determineCoM([F; G]);
Mechanism.Mass = struct('AB', 5, 'BCE', 10, 'CD', 5, 'EF', 10, 'FG', 5);
Mechanism.MassMoI = struct('AB', 0.1, 'BCE', 0.2, 'CD', 0.1, 'EF', 0.2, 'FG', 0.1);
Mechanism = addLinkAngles(Mechanism, struct('AB', 'A', 'BCE', 'B', 'CD', 'D', 'EF', 'E', 'FG', 'G'));
end

function Mechanism = buildTeachingFourBar()
A = [0, 0, 0];
B = [1.52, 0, 0];
C = [4.23, 3.029, 0];
D = [4.572, 0, 0];
E = [4.79, 1.632, 0];
F = [2.548, 1.958, 0];
G = [2.053, 3.543, 0];
H = [0.7598, 1.0278, 0];
I = [4.1798, 1.9520, 0];

Mechanism = baseMechanism(struct('A', A, 'B', B, 'C', C, 'D', D));
Mechanism.TracerPoint = struct('E', E, 'F', F, 'G', G, 'H', H, 'I', I);
Mechanism.LinkCoM.ABH = [-6.38, 2.39, 0];
Mechanism.LinkCoM.BCFG = [185.73, 209.10, 0];
Mechanism.LinkCoM.CDEI = [472.56, -20.80, 0];
Mechanism.Mass = struct('ABH', 10.458382, 'BCFG', 0.626202, 'CDEI', 4.901229);
Mechanism.MassMoI = struct('ABH', 52777966.276354, 'BCFG', 10871793.503827, 'CDEI', 63343618.03601);
Mechanism = addLinkAngles(Mechanism, struct('ABH', 'A', 'BCFG', 'B', 'CDEI', 'C'));
Mechanism.Angle.Joint.E = angleVector(E, D);
Mechanism.Angle.Joint.F = angleVector(F, C) + [0, 0, 180];
Mechanism.Angle.Joint.G = angleVector(G, B);
Mechanism.Angle.Joint.H = angleVector(H, A);
Mechanism.Angle.Joint.I = angleVector(I, D);
end

function Mechanism = buildTeachingSliderCrank()
A = [13.79, 10.01, 0];
B = [13.79, 13.82, 0];
C = [-0.97, 10.01, 0];
E = [13.79, 13.82, 0];

Mechanism = baseMechanism(struct('A', A, 'B', B, 'C', C));
Mechanism.TracerPoint = struct('E', E);
Mechanism.Theta = 0;
Mechanism.LinkCoM.AB = [0, 0.1, 0];
Mechanism.LinkCoM.BCE = [0.5, 0.7, 0];
Mechanism.Mass = struct('AB', 1.08532, 'BCE', 0.50144, 'Piston', 1.31788);
Mechanism.MassMoI = struct('AB', 0.0004647594, 'BCE', 0.0030344427);
Mechanism = addLinkAngles(Mechanism, struct('AB', 'A', 'BCE', 'B'));
Mechanism.Angle.Joint.E = angleVector(E, B);
end

function Mechanism = buildSliderCrankTracer()
A = [0, 0, 0];
B = [4, 2, 0];
C = [12, 0, 0];
D = [20, 2, 0];

Mechanism = baseMechanism(struct('A', A, 'B', B, 'C', C));
Mechanism.TracerPoint = struct('D', D);
Mechanism.LinkCoM.AB = GeneralUtils.determineCoM([A; B]);
Mechanism.LinkCoM.BCD = GeneralUtils.determineCoM([B; C; D]);
Mechanism.Mass = struct('AB', 5, 'BCD', 10);
Mechanism.MassMoI = struct('AB', 0.1, 'BCD', 0.2);
end

function Mechanism = baseMechanism(joints)
Mechanism = struct();
Mechanism.Joint = joints;
Mechanism.TracerPoint = struct();
Mechanism.LinkCoM = struct();
Mechanism.Angle = struct('Link', struct(), 'Joint', struct());
end

function Mechanism = addLinkAngles(Mechanism, anchors)
linkNames = fieldnames(Mechanism.LinkCoM);
for i = 1:numel(linkNames)
    linkName = linkNames{i};
    anchorName = anchors.(linkName);
    Mechanism.Angle.Link.(linkName) = angleVector(Mechanism.LinkCoM.(linkName), Mechanism.Joint.(anchorName));
end
end

function value = angleVector(point, anchor)
value = [0, 0, rad2deg(atan2(point(2) - anchor(2), point(1) - anchor(1)))];
end
