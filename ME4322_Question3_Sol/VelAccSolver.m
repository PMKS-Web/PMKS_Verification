clc;
close all
clear all;

%%
load('Kin/Pos/A')
load('Kin/Pos/B')
load('Kin/Pos/C')
load('Kin/Pos/D')
load('Kin/Pos/E')
load('Kin/Pos/F')
load('Kin/Pos/G')

WAB=zeros(10,3);
WBCE=zeros(10,3);
WCD=zeros(10,3);
WEF=zeros(10,3);
WFG=zeros(10,3);

V_a=zeros(10,3);
V_b=zeros(10,3);
V_c=zeros(10,3);
V_d=zeros(10,3);
V_e=zeros(10,3);
V_f=zeros(10,3);
V_g=zeros(10,3);

V_ab_com=zeros(10,3);
V_bce_com=zeros(10,3);
V_cd_com=zeros(10,3);
V_ef_com=zeros(10,3);
V_fg_com=zeros(10,3);

AAB=zeros(10,3);
ABCE=zeros(10,3);
ACD=zeros(10,3);
AEF=zeros(10,3);
AFG=zeros(10,3);

A_a=zeros(10,3);
A_b=zeros(10,3);
A_c=zeros(10,3);
A_d=zeros(10,3);
A_e=zeros(10,3);
A_f=zeros(10,3);
A_g=zeros(10,3);

A_ab_com=zeros(10,3);
A_bce_com=zeros(10,3);
A_cd_com=zeros(10,3);
A_ef_com=zeros(10,3);
A_fg_com=zeros(10,3);

for theta=1:1:10
    % Coordinates of joints
    A = A_vec(theta,:);
    B = B_vec(theta,:);
    C = C_vec(theta,:);
    D = D_vec(theta,:);
    E = E_vec(theta,:);
    F = F_vec(theta,:);
    G = G_vec(theta,:);

    % Centers of Mass of each Link
    AB_com = (A+B)/2;
    BCE_com = (B+C+E)/3;
    CD_com = (C+D)/2;
    EF_com = (E+F)/2;
    FG_com = (F+G)/2;

    %% Velocity loops
    %velocity equations from given loops
    syms wBCE wCD wEF wFG
    omegaAB=[0 0 10];
    omegaBCE=[0 0 wBCE];
    omegaCD=[0 0 wCD];
    omegaEF=[0 0 wEF];
    omegaFG=[0 0 wFG];

    % A->B->C->D->A
    % V_ba + V_cb + V_dc + V_ad = 0
    eqn1=velSolver(omegaAB,B-A)+velSolver(omegaBCE,C-B)+velSolver(omegaCD,D-C)==0;

    % A->B->E->F->G->A
    % V_ba + V_eb + V_fe + V_gf + V_ag = 0
    eqn2=velSolver(omegaAB,B-A)+velSolver(omegaBCE,E-B)+velSolver(omegaEF,F-E)+velSolver(omegaFG,G-F)==0;
    
    solution=solve([eqn1, eqn2],[wBCE wCD wEF wFG]);

    % Store all the determined angular velocities
    WAB(theta,:)=[0 0 10];
    WBCE(theta,:)=[0 0 solution.wBCE]; %angular velocity of BCE
    WCD(theta,:)=[0 0 solution.wCD]; %angular velocity of CD
    WEF(theta,:)=[0 0 solution.wEF]; %angular velocity of EF
    WFG(theta,:)=[0 0 solution.wFG]; %angular velocity of FG


    % Determine the velocities at each joint
    V_a(theta,:) = [0 0 0];
    V_b(theta,:) = velSolver(WAB(theta,:),B-A);
    V_c(theta,:) = velSolver(WCD(theta,:),D-C);
    V_d(theta,:) = [0 0 0];
    V_e(theta,:) = velSolver(WBCE(theta,:),E-B) + V_b(theta,:);
    V_f(theta,:) = velSolver(WFG(theta,:),F-G);
    V_g(theta,:) = [0 0 0];

    % Determine the velocities at each link's center of mass
    V_ab_com(theta,:) = velSolver(WAB(theta,:),AB_com - A);
    V_bce_com(theta,:) =  velSolver(WBCE(theta,:),BCE_com - B) + V_b(theta,:);
    V_cd_com(theta,:) = velSolver(WCD(theta,:),CD_com - D);
    V_ef_com(theta,:) =  velSolver(WEF(theta,:),EF_com - E) + V_e(theta,:);
    V_fg_com(theta,:) = velSolver(WFG(theta,:),FG_com - G);

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
    eqn1=accSolver(WAB(theta,:),alphaAB, B-A)+accSolver(WBCE(theta,:),alphaBCE,C-B)+accSolver(WCD(theta,:),alphaCD,D-C)==0;

    % A->B->E->F->G->A
    % A_ba + A_eb + A_fe + A_gf + A_ag = 0
    eqn2=accSolver(WAB(theta,:),alphaAB,B-A)+accSolver(WBCE(theta,:),alphaBCE,E-B)+accSolver(WEF(theta,:),alphaEF,F-E)+accSolver(WFG(theta,:),alphaFG,G-F)==0;
    
    solution=solve([eqn1, eqn2],[aBCE aCD aEF aFG]);

    % Store all the determined angular accelerations
    AAB(theta,:)=[0 0 10];
    ABCE(theta,:)=[0 0 solution.aBCE]; %angular acceleration of CD
    ACD(theta,:)=[0 0 solution.aCD]; %angular acceleration of CD
    AEF(theta,:)=[0 0 solution.aEF]; %angular acceleration of CD
    AFG(theta,:)=[0 0 solution.aFG]; %angular acceleration of BC


    % Determine the accelerations at each joint
    A_a(theta,:) = [0 0 0];
    A_b(theta,:) = accSolver(WAB(theta,:), AAB(theta,:),B-A);
    A_c(theta,:) = accSolver(WCD(theta,:), ABCE(theta,:),D-C);
    A_d(theta,:) = [0 0 0];
    A_e(theta,:) = accSolver(WBCE(theta,:), ABCE(theta,:),E-B) + A_b(theta,:);
    A_f(theta,:) = accSolver(WFG(theta,:),AFG(theta,:),F-G);
    A_g(theta,:) = [0 0 0];

    % Determine the accelerations at each link's center of mass
    A_ab_com(theta,:) = accSolver(WAB(theta,:),AAB(theta,:),AB_com - A);
    A_bce_com(theta,:) =  accSolver(WBCE(theta,:),ABCE(theta,:),BCE_com - B) + A_b(theta,:);
    A_cd_com(theta,:) = accSolver(WCD(theta,:),ACD(theta,:),CD_com - D);
    A_ef_com(theta,:) =  accSolver(WEF(theta,:),AEF(theta,:),EF_com - E) + A_e(theta,:);
    A_fg_com(theta,:) = accSolver(WFG(theta,:),AFG(theta,:),FG_com - G);
end

% Directory for saving the results
checkDirectory('Kin/LinVel/Joint');
checkDirectory('Kin/LinVel/Link');
checkDirectory('Kin/AngVel');
checkDirectory('Kin/LinAcc/Joint');
checkDirectory('Kin/LinAcc/Link');
checkDirectory('Kin/AngAcc');

save('Kin/LinVel/Joint/A', 'V_a')
save('Kin/LinVel/Joint/B', 'V_b')
save('Kin/LinVel/Joint/C', 'V_c')
save('Kin/LinVel/Joint/D', 'V_d')
save('Kin/LinVel/Joint/E', 'V_e')
save('Kin/LinVel/Joint/F', 'V_f')
save('Kin/LinVel/Joint/G', 'V_g')

save('Kin/LinVel/Link/AB', 'V_ab_com')
save('Kin/LinVel/Link/BCE', 'V_bce_com')
save('Kin/LinVel/Link/CD', 'V_cd_com')
save('Kin/LinVel/Link/EF', 'V_ef_com')
save('Kin/LinVel/Link/FG', 'V_fg_com')

save('Kin/AngVel/AB', 'WAB')
save('Kin/AngVel/BCE', 'WBCE')
save('Kin/AngVel/CD', 'WCD')
save('Kin/AngVel/EF', 'WEF')
save('Kin/AngVel/FG', 'WFG')

save('Kin/LinAcc/Joint/A', 'A_a')
save('Kin/LinAcc/Joint/B', 'A_b')
save('Kin/LinAcc/Joint/C', 'A_c')
save('Kin/LinAcc/Joint/D', 'A_d')
save('Kin/LinAcc/Joint/E', 'A_e')
save('Kin/LinAcc/Joint/F', 'A_f')
save('Kin/LinAcc/Joint/G', 'A_g')

save('Kin/LinAcc/Link/AB', 'A_ab_com')
save('Kin/LinAcc/Link/BCE', 'A_bce_com')
save('Kin/LinAcc/Link/CD', 'A_cd_com')
save('Kin/LinAcc/Link/EF', 'A_ef_com')
save('Kin/LinAcc/Link/FG', 'A_fg_com')

save('Kin/AngAcc/AB', 'AAB')
save('Kin/AngAcc/BCE', 'ABCE')
save('Kin/AngAcc/CD', 'ACD')
save('Kin/AngAcc/EF', 'AEF')
save('Kin/AngAcc/FG', 'AFG')

function vel = velSolver(w, r)
vel = cross(w,r);
end

function acc = accSolver(w,a,r)
acc = cross(w,cross(w,r)) + cross(a,r);
end

function checkDirectory(saveDir)
% Check if the directory exists, if not, create it
if ~exist(saveDir, 'dir')
    mkdir(saveDir);
end
end