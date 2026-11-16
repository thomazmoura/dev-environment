// The code actions the server offers, in the order they're listed (see ../../common/Features.cs).
// No "Toggle ;": Postgres requires every statement's
namespace SqlAssist.Postgres.CodeActions;

public static class CodeActions
{
    public static readonly ICodeAction[] All =
    {
        new ExpandStar(),
    };
}
