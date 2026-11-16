// The completions the server offers, every one asked on each request (see ../../common/Features.cs)
namespace SqlAssist.Postgres.Completions;

public static class Completions
{
    public static readonly ICompletion[] All =
    {
        new JoinConditions(),
        new InsertColumns(),
    };
}
