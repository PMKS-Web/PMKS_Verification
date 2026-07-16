function config = verification_case_definition(caseName, repoRoot)
%VERIFICATION_CASE_DEFINITION Canonical inputs and rigid constraints for a case.

caseName = char(caseName);
config = struct();
config.name = caseName;
config.hasDynamics = false;
config.scenarios = zeros(0, 3);

switch caseName
    case 'watt_i'
        config.sourceDirectory = fullfile(repoRoot, 'Mechanisms', 'Watt_I');
        config.speedRpm = 10;
        config.inputSpeed = config.speedRpm * pi / 30;
        config.hasDynamics = true;
        config.scenarios = [1 0 0; 1 1 0];
        config.constraints = {
            'A', 'B';
            'B', 'C';
            'B', 'D';
            'C', 'D';
            'D', 'E';
            'E', 'F';
            'C', 'F';
            'C', 'G';
            'F', 'G';
            'A', 'CoM.AB';
            'B', 'CoM.BCD';
            'D', 'CoM.DE';
            'E', 'CoM.EF';
            'G', 'CoM.CFG'};

    case 'stephenson_iii_example_2'
        config.sourceDirectory = fullfile(repoRoot, 'Mechanisms', 'Stephenson_III', 'Example_2');
        config.speedRpm = 10;
        config.inputSpeed = config.speedRpm * pi / 30;
        config.hasDynamics = true;
        config.scenarios = [1 0 0; 1 1 0];
        config.constraints = {
            'A', 'B';
            'B', 'C';
            'B', 'E';
            'C', 'E';
            'C', 'D';
            'E', 'F';
            'F', 'G';
            'A', 'CoM.AB';
            'B', 'CoM.BCE';
            'C', 'CoM.CD';
            'E', 'CoM.EF';
            'F', 'CoM.FG'};

    case 'teaching_four_bar'
        config.sourceDirectory = fullfile(repoRoot, 'Mechanisms', 'Four_Bar_Mechanism', 'TeachingLab_Four_Bar');
        config.speedRpm = 10.31;
        config.inputSpeed = 10.31 * 2 * pi / 60;
        config.constraints = {
            'A', 'B';
            'B', 'C';
            'C', 'D';
            'C', 'E';
            'D', 'E';
            'B', 'F';
            'C', 'F';
            'B', 'G';
            'C', 'G';
            'A', 'H';
            'B', 'H';
            'C', 'I';
            'D', 'I';
            'A', 'CoM.ABH';
            'B', 'CoM.BCFG';
            'C', 'CoM.CDEI'};

    case 'teaching_slider_crank'
        config.sourceDirectory = fullfile(repoRoot, 'Mechanisms', 'Four_Bar_Slider', 'TeachingLab_Slider_Crank');
        config.speedRpm = 15.1;
        config.inputSpeed = 15.1 * 2 * pi / 60;
        config.constraints = {
            'A', 'B';
            'B', 'C';
            'B', 'E';
            'C', 'E';
            'A', 'CoM.AB';
            'B', 'CoM.BCE'};

    case 'slider_crank_tracer'
        config.sourceDirectory = fullfile(repoRoot, 'Mechanisms', 'Four_Bar_Slider', 'Slider_Crank_Tracer_Point');
        config.speedRpm = 10;
        config.inputSpeed = config.speedRpm * pi / 30;
        config.constraints = {
            'A', 'B';
            'B', 'C';
            'B', 'D';
            'C', 'D';
            'A', 'CoM.AB';
            'B', 'CoM.BCD'};

    otherwise
        error('Verification:UnknownCase', 'Unknown verification case: %s', caseName);
end

if ~isfolder(config.sourceDirectory)
    error('Verification:MissingSource', 'Case source directory does not exist: %s', config.sourceDirectory);
end

config.speedField = ['f' strrep(num2str(config.speedRpm), '.', '_') 'RPM'];
end
