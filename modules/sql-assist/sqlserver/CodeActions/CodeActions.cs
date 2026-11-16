// The code actions the server offers, in the order they're listed (see ../../common/Features.cs)
namespace SqlAssist.SqlServer.CodeActions;

public static class CodeActions
{
    public static readonly ICodeAction[] All =
    {
        new ExpandStar(),
        new ToggleSemicolon(),
        new ToggleAllSemicolons(),
    };
}
