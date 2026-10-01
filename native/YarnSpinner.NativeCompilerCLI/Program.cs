// ======================================================================== //
//                    Yarn Spinner for Godot (GDScript)                     //
// ======================================================================== //
//
// Native CLI compiler — reads JSON from stdin, writes JSON to stdout!
// Same protocol as the shared library exports, but as a standalone binary.
// Not dependencies as it's compile diwht NativeAOT.
//
// Usage (binaries are named per platform, e.g. ysc-native-linux-x64):
//   echo '{"files":[...]}' | ysc-native-<os>-<arch>
//   echo '{"files":[...],"declarations":[...]}' | ysc-native-<os>-<arch>
//   ysc-native-<os>-<arch> --input job.json
//   ysc-native-<os>-<arch> --version
//
// --input reads the JSON from a file
//
// "declarations" is optional. Each entry declares a function the game
// provides, so the compiler knows its types even where it can't infer them
// (for example, a function call inside a line):
//   {"name": "coin_count", "parameters": ["string"], "returnType": "number"}
// A function that takes any number of extra arguments at the end adds
// "variadicParameterType" with their type...
// Types are "string", "number", "bool" or "any". An entry whose return type
// is missing, unknown or "any" is skipped, and the compiler infers the type
// from context as it would without a declaration! Binaries are per platform now.
//
// ======================================================================== //

using System;
using System.Buffers;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using Google.Protobuf;
using Yarn;
using Yarn.Compiler;

if (args.Length > 0 && (args[0] == "--version" || args[0] == "-v"))
{
    Console.WriteLine(typeof(Yarn.Compiler.Compiler).Assembly.GetName().Version?.ToString() ?? "unknown");
    return 0;
}

string inputJson;
if (args.Length > 0 && args[0] == "--input")
{
    if (args.Length < 2)
    {
        WriteError("--input needs a file path");
        return 1;
    }
    try
    {
        inputJson = File.ReadAllText(args[1], Encoding.UTF8);
    }
    catch (Exception ex)
    {
        WriteError($"Couldn't read input file '{args[1]}': {ex.Message}");
        return 1;
    }
}
else
{
    using var reader = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8);
    inputJson = reader.ReadToEnd();
}

if (string.IsNullOrWhiteSpace(inputJson))
{
    WriteError("No input provided");
    return 1;
}

try
{
    using var doc = JsonDocument.Parse(inputJson);
    var root = doc.RootElement;

    var inputs = new List<ISourceInput>();
    if (root.TryGetProperty("files", out var filesElement))
    {
        foreach (var file in filesElement.EnumerateArray())
        {
            var fileName = file.GetProperty("fileName").GetString() ?? "input.yarn";
            var source = file.GetProperty("source").GetString() ?? "";
            inputs.Add(new CompilationJob.File { FileName = fileName, Source = source });
        }
    }

    if (inputs.Count == 0)
    {
        WriteError("No input files provided");
        return 1;
    }

    var command = root.TryGetProperty("command", out var commandElement) ? commandElement.GetString() : "compile";

    if (command == "tag")
    {
        var excluded = new HashSet<string>();
        if (root.TryGetProperty("excludedLineIDs", out var excludedElement))
        {
            foreach (var id in excludedElement.EnumerateArray())
            {
                var value = id.GetString();
                if (!string.IsNullOrEmpty(value))
                    excluded.Add(value);
            }
        }

        var taggerName = root.TryGetProperty("tagger", out var taggerElement) ? taggerElement.GetString() : "random";
        WriteTagResult(inputs, excluded, taggerName);
        return 0;
    }

    var job = CompilationJob.CreateFromInputs(inputs);
    var functionDeclarations = ReadFunctionDeclarations(root);
    if (functionDeclarations.Count > 0)
        job.Declarations = functionDeclarations;
    var result = Yarn.Compiler.Compiler.Compile(job);

    WriteResult(result);
    return 0;
}
catch (Exception ex)
{
    WriteError(ex.ToString());
    return 1;
}

static List<Declaration> ReadFunctionDeclarations(JsonElement root)
{
    var declarations = new List<Declaration>();
    if (!root.TryGetProperty("declarations", out var element) || element.ValueKind != JsonValueKind.Array)
        return declarations;

    foreach (var entry in element.EnumerateArray())
    {
        if (entry.ValueKind != JsonValueKind.Object)
            continue;

        var name = entry.TryGetProperty("name", out var nameElement) && nameElement.ValueKind == JsonValueKind.String
            ? nameElement.GetString()
            : null;
        if (string.IsNullOrEmpty(name))
            continue;

        var returnType = entry.TryGetProperty("returnType", out var returnElement) ? ParseYarnType(returnElement) : null;
        if (returnType == null || returnType == Types.Any)
            continue;

        var functionType = new FunctionTypeBuilder().WithReturnType(returnType);
        if (entry.TryGetProperty("parameters", out var parameters) && parameters.ValueKind == JsonValueKind.Array)
        {
            foreach (var parameter in parameters.EnumerateArray())
                functionType.WithParameter(ParseYarnType(parameter) ?? Types.Any);
        }

        if (entry.TryGetProperty("variadicParameterType", out var variadicElement))
        {
            var variadicType = ParseYarnType(variadicElement);
            if (variadicType != null)
                functionType.WithVariadicParameterType(variadicType);
        }

        var declaration = new DeclarationBuilder()
            .WithName(name)
            .WithType(functionType.FunctionType);
        if (entry.TryGetProperty("description", out var descriptionElement) && descriptionElement.ValueKind == JsonValueKind.String)
            declaration.WithDescription(descriptionElement.GetString());

        declarations.Add(declaration.Declaration);
    }

    return declarations;
}

static IType? ParseYarnType(JsonElement element)
{
    if (element.ValueKind != JsonValueKind.String)
        return null;
    return element.GetString()?.ToLowerInvariant() switch
    {
        "string" => Types.String,
        "number" => Types.Number,
        "bool" or "boolean" => Types.Boolean,
        "any" => Types.Any,
        _ => null,
    };
}

static void WriteResult(CompilationResult result)
{
    using var stdout = Console.OpenStandardOutput();
    using var w = new Utf8JsonWriter(stdout);

    w.WriteStartObject();

    bool hasErrors = false;
    foreach (var d in result.Diagnostics)
        if (d.Severity == Diagnostic.DiagnosticSeverity.Error) { hasErrors = true; break; }
    w.WriteBoolean("success", !hasErrors && result.Program != null);

    if (result.Program != null)
        w.WriteString("program", Convert.ToBase64String(result.Program.ToByteArray()));
    else
        w.WriteNull("program");

    w.WriteStartObject("stringTable");
    if (result.StringTable != null)
    {
        foreach (var kvp in result.StringTable)
        {
            w.WriteStartObject(kvp.Key);
            w.WriteString("text", kvp.Value.text);
            w.WriteString("nodeName", kvp.Value.nodeName);
            w.WriteNumber("lineNumber", kvp.Value.lineNumber);
            w.WriteString("fileName", kvp.Value.fileName);
            w.WriteBoolean("isImplicitTag", kvp.Value.isImplicitTag);
            w.WriteStartArray("metadata");
            if (kvp.Value.metadata != null)
                foreach (var m in kvp.Value.metadata)
                    w.WriteStringValue(m);
            w.WriteEndArray();
            w.WriteEndObject();
        }
    }
    w.WriteEndObject();

    w.WriteStartArray("declarations");
    foreach (var decl in result.Declarations)
    {
        if (!decl.IsVariable || decl.Name.StartsWith("$Yarn.Internal"))
            continue;
        w.WriteStartObject();
        w.WriteString("name", decl.Name);
        w.WriteString("type", decl.Type.Name);
        w.WriteBoolean("isEnum", decl.Type is Yarn.EnumType);
        w.WriteString("description", decl.Description ?? "");
        w.WriteBoolean("isInlineExpansion", decl.IsInlineExpansion);
        w.WriteString("sourceFileName", decl.SourceFileName ?? "");
        WriteConvertible(w, "defaultValue", decl.DefaultValue);
        w.WriteEndObject();
    }
    w.WriteEndArray();

    w.WriteStartArray("enums");
    foreach (var type in result.UserDefinedTypes)
    {
        if (type is not Yarn.EnumType enumType)
            continue;
        w.WriteStartObject();
        w.WriteString("name", enumType.Name);
        w.WriteString("description", enumType.Description ?? "");
        w.WriteString("rawType", enumType.RawType.Name);
        w.WriteStartArray("cases");
        foreach (var enumCase in enumType.EnumCases)
        {
            w.WriteStartObject();
            w.WriteString("name", enumCase.Key);
            w.WriteString("description", enumCase.Value.Description ?? "");
            WriteConvertible(w, "value", enumCase.Value.Value);
            w.WriteEndObject();
        }
        w.WriteEndArray();
        w.WriteEndObject();
    }
    w.WriteEndArray();

    w.WriteStartArray("diagnostics");
    foreach (var diag in result.Diagnostics)
    {
        w.WriteStartObject();
        w.WriteString("message", diag.Message);
        w.WriteString("severity", diag.Severity.ToString().ToLowerInvariant());
        w.WriteString("fileName", diag.FileName ?? "");
        w.WriteNumber("line", diag.Range?.Start.Line ?? -1);
        w.WriteNumber("column", diag.Range?.Start.Character ?? -1);
        w.WriteString("code", diag.Code ?? "");
        w.WriteEndObject();
    }
    w.WriteEndArray();

    w.WriteEndObject();
    w.Flush();
    Console.WriteLine(); // trailing newline
}

static void WriteConvertible(Utf8JsonWriter w, string name, IConvertible? value)
{
    switch (value)
    {
        case null:
            w.WriteNull(name);
            break;
        case bool b:
            w.WriteBoolean(name, b);
            break;
        case string str:
            w.WriteString(name, str);
            break;
        default:
            w.WriteNumber(name, value.ToDouble(System.Globalization.CultureInfo.InvariantCulture));
            break;
    }
}

static void WriteTagResult(List<ISourceInput> inputs, HashSet<string> excluded, string? taggerName)
{
    var files = new List<CompilationJob.File>();
    foreach (var input in inputs)
        if (input is CompilationJob.File file)
            files.Add(file);

    var stringsJob = CompilationJob.CreateFromInputs(inputs);
    stringsJob.CompilationType = CompilationJob.Type.StringsOnly;
    var stringsResult = Yarn.Compiler.Compiler.Compile(stringsJob);
    if (stringsResult.StringTable != null)
        foreach (var kvp in stringsResult.StringTable)
            if (!kvp.Value.isImplicitTag)
                excluded.Add(kvp.Key);

    using var stdout = Console.OpenStandardOutput();
    using var w = new Utf8JsonWriter(stdout);

    w.WriteStartObject();
    w.WriteBoolean("success", true);

    var errors = new List<(string Message, string FileName, int Line)>();

    w.WriteStartArray("files");
    foreach (var file in files)
    {
        ILineTagGenerator tagger = taggerName == "descriptive"
            ? new DescriptiveLineTagGenerator()
            : new RandomLineTagGenerator();

        var tagged = Utility.TagLines(file, excluded, tagger);
        foreach (var id in tagged.LineIDs)
            excluded.Add(id);

        foreach (var ex in tagged.TagExceptions)
        {
            var message = ex is ILineTagGenerator.CompilationTagException
                ? "The file contains errors, so no line tags were added to it."
                : ex.Message;
            errors.Add((message, string.IsNullOrEmpty(ex.SourceFile) ? file.FileName : ex.SourceFile!, ex.LineNumber));
        }

        var modifiedSource = tagged.ModifiedSource ?? file.Source;
        w.WriteStartObject();
        w.WriteString("fileName", file.FileName);
        w.WriteBoolean("modified", modifiedSource != file.Source);
        w.WriteString("source", modifiedSource);
        w.WriteEndObject();
    }
    w.WriteEndArray();

    w.WriteStartArray("errors");
    foreach (var error in errors)
    {
        w.WriteStartObject();
        w.WriteString("message", error.Message);
        w.WriteString("fileName", error.FileName);
        w.WriteNumber("line", error.Line);
        w.WriteEndObject();
    }
    w.WriteEndArray();

    w.WriteEndObject();
    w.Flush();
    Console.WriteLine();
}

static void WriteError(string message)
{
    using var stdout = Console.OpenStandardOutput();
    using var w = new Utf8JsonWriter(stdout);
    w.WriteStartObject();
    w.WriteBoolean("success", false);
    w.WriteNull("program");
    w.WriteStartObject("stringTable"); w.WriteEndObject();
    w.WriteStartArray("diagnostics");
    w.WriteStartObject();
    w.WriteString("message", message);
    w.WriteString("severity", "error");
    w.WriteString("fileName", "");
    w.WriteNumber("line", -1);
    w.WriteNumber("column", -1);
    w.WriteString("code", "");
    w.WriteEndObject();
    w.WriteEndArray();
    w.WriteEndObject();
    w.Flush();
    Console.WriteLine();
}
