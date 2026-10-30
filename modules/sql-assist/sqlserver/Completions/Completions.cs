// The completions the server offers, every one asked on each request (see Features.cs)
namespace SqlServerAssist.Completions;

public static class Completions
{
    public static readonly ICompletion[] All =
    {
        new JoinConditions(),
        new InsertColumns(),
    };

    // Word characters, as the T-SQL names typed after ON or ( are matched
    public const string Word = "[A-Za-z0-9_]";
}
