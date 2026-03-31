// ======================================================================== //
//                    Yarn Spinner for Godot (GDScript)                     //
// ======================================================================== //
//                                                                          //
// NativeAOT exports for the Yarn Spinner compiler.                         //
// Produces a shared library (.dylib/.dll/.so) callable from GDExtension.   //
//                                                                          //
// ======================================================================== //

using System;
using System.Buffers;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Google.Protobuf;
using Yarn.Compiler;

public static unsafe class NativeExports
{
    [UnmanagedCallersOnly(EntryPoint = "ysc_compile")]
    public static IntPtr Compile(byte* inputJsonUtf8, int inputLength)
    {
        try
        {
            var inputJson = Encoding.UTF8.GetString(inputJsonUtf8, inputLength);
            var result = CompileFromJson(inputJson);
            return AllocUtf8String(result);
        }
        catch (Exception ex)
        {
            return AllocUtf8String(WriteErrorJson(ex.ToString()));
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "ysc_string_length")]
    public static int StringLength(IntPtr str)
    {
        if (str == IntPtr.Zero) return 0;
        int len = 0;
        byte* p = (byte*)str;
        while (p[len] != 0) len++;
        return len;
    }

    [UnmanagedCallersOnly(EntryPoint = "ysc_free_string")]
    public static void FreeString(IntPtr str)
    {
        if (str != IntPtr.Zero)
            NativeMemory.Free(str.ToPointer());
    }

    [UnmanagedCallersOnly(EntryPoint = "ysc_version")]
    public static IntPtr Version()
    {
        var version = typeof(Yarn.Compiler.Compiler).Assembly.GetName().Version?.ToString() ?? "unknown";
        return AllocUtf8String(version);
    }

    // -----------------------------------------------------------------------

    private static string CompileFromJson(string inputJson)
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
            return WriteErrorJson("No input files provided");

        var job = CompilationJob.CreateFromInputs(inputs);
        var compilationResult = Yarn.Compiler.Compiler.Compile(job);

        return WriteResultJson(compilationResult);
    }

    // Manual JSON writing — NativeAOT doesn't support reflection-based JsonSerializer
    private static string WriteResultJson(CompilationResult result)
    {
        using var stream = new MemoryStream();
        using var w = new Utf8JsonWriter(stream);

        w.WriteStartObject();

        // success
        bool hasErrors = false;
        foreach (var d in result.Diagnostics)
            if (d.Severity == Diagnostic.DiagnosticSeverity.Error) { hasErrors = true; break; }
        w.WriteBoolean("success", !hasErrors && result.Program != null);

        // program (base64)
        if (result.Program != null)
            w.WriteString("program", Convert.ToBase64String(result.Program.ToByteArray()));
        else
            w.WriteNull("program");

        // stringTable
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

        // diagnostics
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
        return Encoding.UTF8.GetString(stream.ToArray());
    }

    private static string WriteErrorJson(string message)
    {
        using var stream = new MemoryStream();
        using var w = new Utf8JsonWriter(stream);
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
        return Encoding.UTF8.GetString(stream.ToArray());
    }

    private static IntPtr AllocUtf8String(string str)
    {
        var bytes = Encoding.UTF8.GetBytes(str);
        var ptr = (byte*)NativeMemory.Alloc((nuint)(bytes.Length + 1));
        bytes.CopyTo(new Span<byte>(ptr, bytes.Length));
        ptr[bytes.Length] = 0;
        return (IntPtr)ptr;
    }
}
