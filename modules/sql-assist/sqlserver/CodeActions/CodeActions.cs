// The code actions the server offers, in the order they're listed (see Features.cs)
namespace SqlServerAssist.CodeActions;

public static class CodeActions
{
    public static readonly ICodeAction[] All =
    {
        new ExpandStar(),
        new ToggleSemicolon(),
        new ToggleAllSemicolons(),
    };
}
