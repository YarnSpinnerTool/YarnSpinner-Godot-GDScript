// ======================================================================== //
//                    Yarn Spinner for Godot (GDScript)                     //
// ======================================================================== //
//
// Native CLI compiler — reads JSON from stdin, writes JSON to stdout.
// Same protocol as the shared library exports, but as a standalone binary.
// Zero .NET runtime dependency (NativeAOT compiled).
//
// Usage:
//   echo '{"files":[...]}' | ysc-native
//   ysc-native --version
//
// ======================================================================== //

using System;
using System.Buffers;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using Google.Protobuf;
using Yarn.Compiler;

if (args.Length > 0 && (args[0] == "--version" || args[0] == "-v"))
{
    Console.WriteLine(typeof(Yarn.Compiler.Compiler).Assembly.GetName().Version?.ToString() ?? "unknown");
    return 0;
}

// Read all of stdin
string inputJson;
using (var reader = new StreamReader(Console.OpenStandardInput(), Encoding.UTF8))
{
    inputJson = reader.ReadToEnd();
}

if (string.IsNullOrWhiteSpace(inputJson))
{
    WriteError("No input provided on stdin");
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

    var job = CompilationJob.CreateFromInputs(inputs);
    var result = Yarn.Compiler.Compiler.Compile(job);

    WriteResult(result);
    return 0;
}
catch (Exception ex)
{
    WriteError(ex.ToString());
    return 1;
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
            w.WriteStartArray("metadata");
            if (kvp.Value.metadata != null)
                foreach (var m in kvp.Value.metadata)
                    w.WriteStringValue(m);
            w.WriteEndArray();
            w.WriteEndObject();
        }
    }
    w.WriteEndObject();

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
