// What each dialect's parser reads from a document for the features (Features/). Offsets are
// string indices (UTF-16), the end excluded.
namespace SqlAssist;

// The * (or o.*) of a select list: the names its FROM's tables and views go by there (alias,
// else name, as written), whether that name is an alias, and the text of its FROM and of its
// statement's CTEs. Qualifier and With are null when it has none
public record Star(int Start, int End, string? Qualifier, List<string> Sources, List<bool> Aliased, string? With, string From);

// A table of a join, schema and table unquoted (schema null when not written), and what it
// goes by there (alias, else name, as written)
public record JoinTable(string? Schema, string Table, string Name);

// The tables a join joins (several for a parenthesized join), and the ones before it, nearest last
public record Join(List<JoinTable> Joined, List<JoinTable> Earlier);
