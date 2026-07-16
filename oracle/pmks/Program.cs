using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using PMKS;

const string PmksRepository = "https://github.com/DesignEngrLab/PMKS";
const string PmksCommit = "2a0a6fca957dd19844567702af663f607dc15dfe";
var options = Arguments.Parse(args);
var manifests = Directory.GetDirectories(options.CasesRoot)
    .Select(directory => Path.Combine(directory, "case.json"))
    .Where(File.Exists)
    .Select(LoadManifest)
    .OrderBy(manifest => manifest.CaseId)
    .ToArray();

if (manifests.Length != 5)
    throw new InvalidOperationException($"Expected five v1 cases, found {manifests.Length}.");

foreach (var manifest in manifests)
{
    var topology = PmksTopology.Build(manifest);
    var positive = GenerateRun(manifest, topology, +1);
    var positiveRepeat = GenerateRun(manifest, topology, +1);
    var negative = GenerateRun(manifest, topology, -1);
    AssertRepeatable(manifest.CaseId, positive, positiveRepeat);
    AssertRunCapabilities(manifest, topology, positive, negative);
    WriteCase(options.OutputRoot, manifest, topology, positive, negative);
    Console.WriteLine(
        $"{manifest.CaseId}: +{positive.Rows.Count}/-{negative.Rows.Count} canonical samples " +
        $"(raw {positive.RawSampleCount}/{negative.RawSampleCount})");
}

Console.WriteLine("PMKS_ORACLE=PASS");

static CaseManifest LoadManifest(string path)
{
    var manifest = JsonSerializer.Deserialize<CaseManifest>(File.ReadAllText(path), JsonOptions())
        ?? throw new InvalidOperationException($"Could not parse {path}.");
    if (manifest.SchemaVersion != 1) throw new InvalidOperationException($"{path} is not v1.");
    return manifest;
}

static RunResult GenerateRun(CaseManifest manifest, PmksTopology topology, int direction)
{
    var simulator = new Simulator(
        topology.LinkIds.Select(value => value.ToArray()).ToList(),
        topology.JointTypes.ToList(),
        topology.DriverIndex,
        topology.Positions.Select(value => value.ToArray()).ToList());
    simulator.InputSpeed = direction * manifest.Input.SpeedRadS;
    simulator.AngleIncrement = manifest.Input.AngleIncrementRad;
    if (double.IsFinite(simulator.MaxSmoothingError))
        throw new InvalidOperationException($"{manifest.CaseId}: AngleIncrement did not disable smoothing.");
    if (!simulator.FindFullMovement())
        throw new InvalidOperationException($"{manifest.CaseId}: FindFullMovement returned false.");

    var candidates = new Dictionary<int, List<CanonicalRow>>();
    for (var index = 0; index < simulator.JointParameters.Count; index++)
    {
        var time = simulator.JointParameters.Times[index];
        var tick = checked((int)Math.Round(time * simulator.InputSpeed / simulator.AngleIncrement));
        var row = new CanonicalRow(
            tick,
            time,
            Copy(simulator.JointParameters.Parameters[index]),
            Copy(simulator.LinkParameters.Parameters[index]));
        if (!candidates.TryGetValue(tick, out var rows))
        {
            rows = new List<CanonicalRow>();
            candidates.Add(tick, rows);
        }
        rows.Add(row);
    }

    var canonical = candidates
        .Select(pair => pair.Value.OrderBy(row => row, CanonicalRowComparer.Instance).First())
        .OrderBy(row => direction * row.Tick)
        .ToList();
    return new RunResult(direction, simulator.JointParameters.Count, simulator.CycleType, canonical);
}

static void AssertRepeatable(string caseId, RunResult first, RunResult second)
{
    if (first.Rows.Count != second.Rows.Count)
        throw new InvalidOperationException($"{caseId}: canonical PMKS row counts are not repeatable.");
    for (var row = 0; row < first.Rows.Count; row++)
    {
        var left = first.Rows[row].ComparableValues();
        var right = second.Rows[row].ComparableValues();
        if (left.Length != right.Length) throw new InvalidOperationException($"{caseId}: shape changed.");
        for (var value = 0; value < left.Length; value++)
        {
            var scale = Math.Max(1.0, Math.Max(Math.Abs(left[value]), Math.Abs(right[value])));
            var ulp = Math.Max(
                Math.Abs(Math.BitIncrement(left[value]) - left[value]),
                Math.Abs(Math.BitIncrement(right[value]) - right[value]));
            if (Math.Abs(left[value] - right[value]) > 8 * ulp + 1e-12 * scale)
                throw new InvalidOperationException(
                    $"{caseId}: canonical PMKS output is not repeatable at row {row}, value {value}.");
        }
    }
}

static void AssertRunCapabilities(
    CaseManifest manifest,
    PmksTopology topology,
    RunResult positive,
    RunResult negative)
{
    if (positive.Rows.Count < 3 || negative.Rows.Count < 3)
        throw new InvalidOperationException($"{manifest.CaseId}: insufficient PMKS movement.");
    if (manifest.Capabilities.Points && topology.PointIndices.Count == 0)
        throw new InvalidOperationException($"{manifest.CaseId}: tracer points were not built.");
    if (manifest.Capabilities.Prismatic)
    {
        foreach (var (jointId, index) in topology.PrismaticIndices)
        {
            var values = positive.Rows.Select(row => row.Joints[index, 6]).ToArray();
            if (values.Max() - values.Min() <= 1e-9 ||
                positive.Rows.Any(row => !double.IsFinite(row.Joints[index, 7]) || !double.IsFinite(row.Joints[index, 8])))
                throw new InvalidOperationException($"{manifest.CaseId}: prismatic state for {jointId} is invalid.");
        }
    }

    foreach (var joint in manifest.Topology.Joints)
    {
        var index = topology.JointIndices[joint.Id];
        var p = positive.Rows.MinBy(row => Math.Abs(row.Tick))!.Joints;
        var n = negative.Rows.MinBy(row => Math.Abs(row.Tick))!.Joints;
        if (Distance(p[index, 0], p[index, 1], n[index, 0], n[index, 1]) > 1e-9)
            throw new InvalidOperationException($"{manifest.CaseId}: +/- runs changed the initial assembly.");
    }
}

static void WriteCase(
    string outputRoot,
    CaseManifest manifest,
    PmksTopology topology,
    RunResult positive,
    RunResult negative)
{
    var caseRoot = Path.Combine(outputRoot, "cases", manifest.CaseId);
    RejectLegacy(caseRoot);
    Directory.CreateDirectory(caseRoot);
    var sourceManifest = Path.Combine(Arguments.Current.CasesRoot, manifest.CaseId, "case.json");
    File.Copy(sourceManifest, Path.Combine(caseRoot, "case.json"), overwrite: true);
    var pmksRoot = Path.Combine(caseRoot, "pmks");
    if (Directory.Exists(pmksRoot)) Directory.Delete(pmksRoot, recursive: true);
    Directory.CreateDirectory(pmksRoot);
    foreach (var folder in new[] { "joints", "points", "com", "links", "prismatic" })
        Directory.CreateDirectory(Path.Combine(pmksRoot, folder));

    var sources = new[] { positive, negative };
    var samples = new List<SourceSample>();
    foreach (var source in sources)
    {
        var rawAngles = source.Rows.Select(row => InputAngle(row, manifest, topology)).ToArray();
        var unwrappedAngles = Unwrap(rawAngles);
        for (var index = 0; index < source.Rows.Count; index++)
        {
            var row = source.Rows[index];
            samples.Add(new SourceSample(
                $"pmks_{(source.Direction > 0 ? "positive" : "negative")}_{index:0000}",
                $"pmks_{(source.Direction > 0 ? "positive" : "negative")}",
                index,
                source.Direction,
                unwrappedAngles[index],
                row.Time,
                JacobianCondition(manifest, topology, row),
                row));
        }
    }

    WriteCsv(
        Path.Combine(pmksRoot, "samples.csv"),
        new[] { "sample_id", "sweep_id", "sweep_index", "input_angle_rad", "input_direction", "time_s", "jacobian_condition", "eligibility" },
        samples.Select(sample => new object[]
        {
            sample.Id, sample.SweepId, sample.SweepIndex, sample.InputAngle, sample.Direction,
            sample.Time, sample.Condition,
            sample.Condition > manifest.Jacobian.SingularConditionThreshold ? "singular" : "eligible"
        }));

    foreach (var joint in manifest.Topology.Joints)
        WritePointSeries(Path.Combine(pmksRoot, "joints", joint.Id + ".csv"), samples, topology.JointIndices[joint.Id]);
    foreach (var point in manifest.Topology.Points)
        WritePointSeries(Path.Combine(pmksRoot, "points", point.Id + ".csv"), samples, topology.PointIndices[point.Id]);
    foreach (var (linkId, index) in topology.ComIndices)
        WritePointSeries(Path.Combine(pmksRoot, "com", linkId + ".csv"), samples, index);

    foreach (var link in manifest.Topology.Links)
    {
        var linkIndex = topology.LinkIndices[link.Id];
        var thetaBySample = new Dictionary<string, double>();
        foreach (var source in sources)
        {
            var sourceSamples = samples.Where(sample => sample.Direction == source.Direction).ToArray();
            var raw = sourceSamples.Select(sample => BasisAngle(sample.Row, link, topology)).ToArray();
            var unwrapped = Unwrap(raw);
            var zeroIndex = source.Rows.FindIndex(row => row.Tick == 0);
            if (zeroIndex < 0) throw new InvalidOperationException($"{manifest.CaseId}: PMKS run lacks tick zero.");
            var initial = unwrapped[zeroIndex];
            for (var index = 0; index < sourceSamples.Length; index++)
                thetaBySample.Add(sourceSamples[index].Id, unwrapped[index] - initial);
        }
        WriteCsv(
            Path.Combine(pmksRoot, "links", link.Id + ".csv"),
            new[] { "sample_id", "theta_delta_rad", "omega_rad_s", "alpha_rad_s2" },
            samples.Select(sample => new object[]
            {
                sample.Id, thetaBySample[sample.Id], sample.Row.Links[linkIndex, 1], sample.Row.Links[linkIndex, 2]
            }));
    }

    foreach (var (jointId, index) in topology.PrismaticIndices)
        WriteCsv(
            Path.Combine(pmksRoot, "prismatic", jointId + ".csv"),
            new[] { "sample_id", "position", "velocity", "acceleration" },
            samples.Select(sample => new object[]
            {
                sample.Id, sample.Row.Joints[index, 6], sample.Row.Joints[index, 7], sample.Row.Joints[index, 8]
            }));

    var metadata = new
    {
        schema_version = 1,
        source_repository = PmksRepository,
        source_commit = PmksCommit,
        license = "MIT",
        angle_increment_rad = manifest.Input.AngleIncrementRad,
        adaptive_smoothing = false,
        runs = new
        {
            positive = new { canonical_rows = positive.Rows.Count },
            negative = new { canonical_rows = negative.Rows.Count }
        },
        canonicalization = "Group by exact one-degree input tick, collapse race-sensitive endpoint duplicates, normalize link angles for repeatability checks."
    };
    File.WriteAllText(
        Path.Combine(pmksRoot, "source-metadata.json"),
        JsonSerializer.Serialize(metadata, JsonOptions()) + Environment.NewLine);
}

static void WritePointSeries(string path, IReadOnlyList<SourceSample> samples, int index) =>
    WriteCsv(
        path,
        new[] { "sample_id", "x", "y", "vx", "vy", "ax", "ay" },
        samples.Select(sample => new object[]
        {
            sample.Id,
            sample.Row.Joints[index, 0], sample.Row.Joints[index, 1],
            sample.Row.Joints[index, 2], sample.Row.Joints[index, 3],
            sample.Row.Joints[index, 4], sample.Row.Joints[index, 5]
        }));

static double JacobianCondition(CaseManifest manifest, PmksTopology topology, CanonicalRow row)
{
    var unknowns = manifest.Jacobian.UnknownJoints;
    var matrix = new double[manifest.Jacobian.LengthConstraints.Count + manifest.Jacobian.GuideConstraints.Count, unknowns.Count * 2];
    for (var constraint = 0; constraint < manifest.Jacobian.LengthConstraints.Count; constraint++)
    {
        var pair = manifest.Jacobian.LengthConstraints[constraint];
        var first = topology.JointIndices[pair[0]];
        var second = topology.JointIndices[pair[1]];
        var dx = row.Joints[first, 0] - row.Joints[second, 0];
        var dy = row.Joints[first, 1] - row.Joints[second, 1];
        var firstInitial = manifest.Topology.Joints.Single(joint => joint.Id == pair[0]).Initial;
        var secondInitial = manifest.Topology.Joints.Single(joint => joint.Id == pair[1]).Initial;
        var length = Distance(firstInitial[0], firstInitial[1], secondInitial[0], secondInitial[1]);
        var derivativeX = dx * manifest.CharacteristicLength / (length * length);
        var derivativeY = dy * manifest.CharacteristicLength / (length * length);
        AddDerivative(matrix, constraint, unknowns, pair[0], derivativeX, derivativeY);
        AddDerivative(matrix, constraint, unknowns, pair[1], -derivativeX, -derivativeY);
    }
    for (var index = 0; index < manifest.Jacobian.GuideConstraints.Count; index++)
    {
        var guide = manifest.Jacobian.GuideConstraints[index];
        var length = Math.Sqrt(guide.Axis[0] * guide.Axis[0] + guide.Axis[1] * guide.Axis[1]);
        AddDerivative(matrix, manifest.Jacobian.LengthConstraints.Count + index, unknowns, guide.Joint,
            -guide.Axis[1] / length, guide.Axis[0] / length);
    }
    var condition = ConditionNumber(matrix);
    return double.IsFinite(condition) ? condition : 1e300;
}

static void AddDerivative(double[,] matrix, int row, IReadOnlyList<string> unknowns, string joint, double x, double y)
{
    var index = unknowns.IndexOf(joint);
    if (index < 0) return;
    matrix[row, 2 * index] = x;
    matrix[row, 2 * index + 1] = y;
}

static double ConditionNumber(double[,] matrix)
{
    var columns = matrix.GetLength(1);
    var normal = new double[columns, columns];
    for (var row = 0; row < matrix.GetLength(0); row++)
    for (var first = 0; first < columns; first++)
    for (var second = 0; second < columns; second++)
        normal[first, second] += matrix[row, first] * matrix[row, second];
    var eigenvalues = SymmetricEigenvalues(normal).Where(value => value > 0).OrderBy(value => value).ToArray();
    if (eigenvalues.Length < columns || eigenvalues[0] <= double.Epsilon) return double.PositiveInfinity;
    return Math.Sqrt(eigenvalues[^1] / eigenvalues[0]);
}

static double[] SymmetricEigenvalues(double[,] source)
{
    var size = source.GetLength(0);
    var matrix = Copy(source);
    for (var iteration = 0; iteration < 100 * size * size; iteration++)
    {
        var p = 0;
        var q = 0;
        var maximum = 0.0;
        for (var row = 0; row < size; row++)
        for (var column = row + 1; column < size; column++)
            if (Math.Abs(matrix[row, column]) > maximum)
            {
                maximum = Math.Abs(matrix[row, column]);
                p = row;
                q = column;
            }
        if (maximum < 1e-15) break;
        var angle = 0.5 * Math.Atan2(2 * matrix[p, q], matrix[q, q] - matrix[p, p]);
        var cosine = Math.Cos(angle);
        var sine = Math.Sin(angle);
        for (var index = 0; index < size; index++)
        {
            if (index == p || index == q) continue;
            var ip = matrix[index, p];
            var iq = matrix[index, q];
            matrix[index, p] = matrix[p, index] = cosine * ip - sine * iq;
            matrix[index, q] = matrix[q, index] = sine * ip + cosine * iq;
        }
        var pp = matrix[p, p];
        var qq = matrix[q, q];
        var pq = matrix[p, q];
        matrix[p, p] = cosine * cosine * pp - 2 * sine * cosine * pq + sine * sine * qq;
        matrix[q, q] = sine * sine * pp + 2 * sine * cosine * pq + cosine * cosine * qq;
        matrix[p, q] = matrix[q, p] = 0;
    }
    return Enumerable.Range(0, size).Select(index => Math.Max(0, matrix[index, index])).ToArray();
}

static double BasisAngle(CanonicalRow row, LinkSpec link, PmksTopology topology)
{
    var first = topology.JointIndices[link.AngleBasis[0]];
    var second = topology.JointIndices[link.AngleBasis[1]];
    return Math.Atan2(row.Joints[second, 1] - row.Joints[first, 1], row.Joints[second, 0] - row.Joints[first, 0]);
}

static double InputAngle(CanonicalRow row, CaseManifest manifest, PmksTopology topology)
{
    var link = manifest.Topology.Links.Single(value => value.Id == manifest.Input.Link);
    return BasisAngle(row, link, topology);
}

static double[] Unwrap(double[] values)
{
    var result = values.ToArray();
    for (var index = 1; index < result.Length; index++)
    {
        while (result[index] - result[index - 1] > Math.PI) result[index] -= 2 * Math.PI;
        while (result[index] - result[index - 1] < -Math.PI) result[index] += 2 * Math.PI;
    }
    return result;
}

static void WriteCsv(string path, IReadOnlyList<string> header, IEnumerable<object[]> rows)
{
    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
    using var writer = new StreamWriter(path, append: false, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    writer.WriteLine(string.Join(',', header));
    foreach (var row in rows) writer.WriteLine(string.Join(',', row.Select(Format)));
}

static string Format(object value) => value switch
{
    double number => number.ToString("G17", CultureInfo.InvariantCulture),
    float number => number.ToString("G9", CultureInfo.InvariantCulture),
    IFormattable formattable => formattable.ToString(null, CultureInfo.InvariantCulture),
    _ => value.ToString() ?? string.Empty
};

static double[,] Copy(double[,] source)
{
    var result = new double[source.GetLength(0), source.GetLength(1)];
    Array.Copy(source, result, source.Length);
    return result;
}

static double Distance(double x1, double y1, double x2, double y2) =>
    Math.Sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));

static void RejectLegacy(string path)
{
    var normalized = path.Replace('\\', '/');
    if (normalized.Contains("/legacy/", StringComparison.OrdinalIgnoreCase) ||
        normalized.Contains("/CSVOutput", StringComparison.OrdinalIgnoreCase))
        throw new InvalidOperationException($"v1 generators reject legacy path {path}.");
}

static JsonSerializerOptions JsonOptions() => new()
{
    PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
    WriteIndented = true
};

internal sealed class Arguments
{
    public static Arguments Current { get; private set; } = null!;
    public required string CasesRoot { get; init; }
    public required string OutputRoot { get; init; }

    public static Arguments Parse(string[] values)
    {
        string? casesRoot = null;
        string? outputRoot = null;
        for (var index = 0; index < values.Length; index++)
        {
            if (values[index] == "--cases-root") casesRoot = values[++index];
            else if (values[index] == "--output-root") outputRoot = values[++index];
            else throw new ArgumentException($"Unknown argument {values[index]}.");
        }
        Current = new Arguments
        {
            CasesRoot = Path.GetFullPath(casesRoot ?? "reference-data/v1/cases"),
            OutputRoot = Path.GetFullPath(outputRoot ?? "artifacts/candidate/reference-data/v1")
        };
        return Current;
    }
}

internal sealed class PmksTopology
{
    public required List<string[]> LinkIds { get; init; }
    public required List<JointType> JointTypes { get; init; }
    public required List<double[]> Positions { get; init; }
    public required int DriverIndex { get; init; }
    public required Dictionary<string, int> JointIndices { get; init; }
    public required Dictionary<string, int> PointIndices { get; init; }
    public required Dictionary<string, int> ComIndices { get; init; }
    public required Dictionary<string, int> PrismaticIndices { get; init; }
    public required Dictionary<string, int> LinkIndices { get; init; }

    public static PmksTopology Build(CaseManifest manifest)
    {
        var linkIds = new List<string[]>();
        var types = new List<JointType>();
        var positions = new List<double[]>();
        var joints = new Dictionary<string, int>();
        var points = new Dictionary<string, int>();
        var coms = new Dictionary<string, int>();
        var prismatics = new Dictionary<string, int>();

        foreach (var joint in manifest.Topology.Joints)
        {
            if (joint.Type == "P")
            {
                var movingLink = joint.Links.Single(link => !Simulator.IsGroundLinkName(link));
                var piston = "__piston_" + joint.Id;
                joints.Add(joint.Id, linkIds.Count);
                linkIds.Add(new[] { movingLink, piston });
                types.Add(JointType.R);
                positions.Add(joint.Initial.ToArray());
                prismatics.Add(joint.Id, linkIds.Count);
                linkIds.Add(new[] { piston, "ground" });
                types.Add(JointType.P);
                var axis = joint.GuideAxis ?? throw new InvalidOperationException($"{joint.Id} lacks guide_axis.");
                positions.Add(new[] { joint.Initial[0], joint.Initial[1], Math.Atan2(axis[1], axis[0]) });
            }
            else
            {
                joints.Add(joint.Id, linkIds.Count);
                linkIds.Add(joint.Links.ToArray());
                types.Add(JointType.R);
                positions.Add(joint.Initial.ToArray());
            }
        }
        foreach (var point in manifest.Topology.Points)
        {
            points.Add(point.Id, linkIds.Count);
            linkIds.Add(new[] { point.Link });
            types.Add(JointType.R);
            positions.Add(point.Initial.ToArray());
        }
        var physicalLinks = manifest.Topology.Links.Select(link => link.Id).ToHashSet();
        foreach (var (link, properties) in manifest.MassProperties)
        {
            if (!physicalLinks.Contains(link)) continue;
            coms.Add(link, linkIds.Count);
            linkIds.Add(new[] { link });
            types.Add(JointType.R);
            positions.Add(properties.ComInitial.ToArray());
        }
        var linkIndices = new Dictionary<string, int>();
        foreach (var link in linkIds.SelectMany(value => value))
        {
            var normalized = Simulator.IsGroundLinkName(link) ? "ground" : link;
            if (!linkIndices.ContainsKey(normalized)) linkIndices.Add(normalized, linkIndices.Count);
        }
        return new PmksTopology
        {
            LinkIds = linkIds,
            JointTypes = types,
            Positions = positions,
            DriverIndex = joints[manifest.Input.Joint],
            JointIndices = joints,
            PointIndices = points,
            ComIndices = coms,
            PrismaticIndices = prismatics,
            LinkIndices = linkIndices
        };
    }
}

internal sealed record CanonicalRow(int Tick, double Time, double[,] Joints, double[,] Links)
{
    public double[] ComparableValues()
    {
        var result = new List<double> { Tick };
        foreach (var value in Joints) result.Add(value);
        for (var row = 0; row < Links.GetLength(0); row++)
        for (var column = 0; column < Links.GetLength(1); column++)
        {
            var value = Links[row, column];
            if (column == 0)
            {
                value %= 2 * Math.PI;
                if (value < 0) value += 2 * Math.PI;
                if (Math.Abs(value - 2 * Math.PI) < 1e-12) value = 0;
            }
            result.Add(value);
        }
        return result.ToArray();
    }
}

internal sealed class CanonicalRowComparer : IComparer<CanonicalRow>
{
    public static CanonicalRowComparer Instance { get; } = new();
    public int Compare(CanonicalRow? first, CanonicalRow? second)
    {
        if (ReferenceEquals(first, second)) return 0;
        if (first is null) return -1;
        if (second is null) return 1;
        var left = first.ComparableValues();
        var right = second.ComparableValues();
        for (var index = 0; index < Math.Min(left.Length, right.Length); index++)
        {
            var comparison = left[index].CompareTo(right[index]);
            if (comparison != 0) return comparison;
        }
        return left.Length.CompareTo(right.Length);
    }
}

internal sealed record RunResult(int Direction, int RawSampleCount, CycleTypes CycleType, List<CanonicalRow> Rows);
internal sealed record SourceSample(string Id, string SweepId, int SweepIndex, int Direction, double InputAngle, double Time, double Condition, CanonicalRow Row);

internal sealed record CaseManifest(
    int SchemaVersion,
    string CaseId,
    double CharacteristicLength,
    TopologySpec Topology,
    InputSpec Input,
    JacobianSpec Jacobian,
    Dictionary<string, MassPropertySpec> MassProperties,
    CapabilitySpec Capabilities);
internal sealed record TopologySpec(List<JointSpec> Joints, List<PointSpec> Points, List<LinkSpec> Links);
internal sealed record JointSpec(string Id, string Type, List<string> Links, double[] Initial, double[]? GuideAxis);
internal sealed record PointSpec(string Id, string Link, double[] Initial);
internal sealed record LinkSpec(string Id, List<string> Joints, List<string> AngleBasis);
internal sealed record InputSpec(string Joint, string Link, double Rpm, double SpeedRadS, double AngleIncrementRad);
internal sealed record JacobianSpec(List<string> UnknownJoints, List<List<string>> LengthConstraints, List<GuideSpec> GuideConstraints, double SingularConditionThreshold);
internal sealed record GuideSpec(string Joint, double[] Axis);
internal sealed record MassPropertySpec(double Mass, double Inertia, double[] ComInitial);
internal sealed record CapabilitySpec(bool Joints, bool Points, bool Com, bool Links, bool Prismatic, bool Dynamics, bool Motiongen);

internal static class ListExtensions
{
    public static int IndexOf<T>(this IReadOnlyList<T> values, T value)
    {
        for (var index = 0; index < values.Count; index++)
            if (EqualityComparer<T>.Default.Equals(values[index], value)) return index;
        return -1;
    }
}
