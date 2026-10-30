// The open documents' text (full sync), with the version the client gave it, and the
// conversions between LSP positions and string offsets
namespace SqlServerAssist;

public sealed class Document
{
    public string Uri { get; }
    public int Version { get; }
    public string Text { get; }
    // The offset each line starts at. Lines end at \n; a \r before it stays in the line,
    // past any character a position points at
    readonly int[] lineStarts;

    public Document(string uri, int version, string text)
    {
        Uri = uri;
        Version = version;
        Text = text;
        var starts = new List<int> { 0 };
        for (int i = 0; i < text.Length; i++)
            if (text[i] == '\n') starts.Add(i + 1);
        lineStarts = starts.ToArray();
    }

    public int Offset(Position position)
    {
        int line = Math.Clamp(position.Line, 0, lineStarts.Length - 1);
        int end = line + 1 < lineStarts.Length ? lineStarts[line + 1] - 1 : Text.Length;
        return Math.Min(lineStarts[line] + Math.Max(position.Character, 0), end);
    }

    public Position Position(int offset)
    {
        offset = Math.Clamp(offset, 0, Text.Length);
        int line = Array.BinarySearch(lineStarts, offset);
        if (line < 0) line = ~line - 1;
        return new Position(line, offset - lineStarts[line]);
    }

    public Range Range(int start, int end) => new(Position(start), Position(end));

    // The text of the line holding offset, from its start up to offset
    public string LineBefore(int offset)
    {
        int line = Position(offset).Line;
        return Text.Substring(lineStarts[line], offset - lineStarts[line]);
    }

    public string Line(int line)
    {
        int start = lineStarts[line];
        int end = line + 1 < lineStarts.Length ? lineStarts[line + 1] - 1 : Text.Length;
        return Text.Substring(start, end - start).TrimEnd('\r');
    }
}

public sealed class Documents
{
    readonly Dictionary<string, Document> open = new();

    public void Set(string uri, int version, string text) => open[uri] = new Document(uri, version, text);

    public void Close(string uri) => open.Remove(uri);

    public Document? Get(string uri) => open.TryGetValue(uri, out var document) ? document : null;
}
