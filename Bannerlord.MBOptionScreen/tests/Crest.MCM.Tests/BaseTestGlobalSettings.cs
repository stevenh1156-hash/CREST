using MCM.Abstractions.Base.Global;

namespace MCM.Tests
{
    public abstract class BaseTestGlobalSettings<T> : AttributeGlobalSettings<T> where T : GlobalSettings, new()
    {
        public override string FolderName => "MCM.Tests";

        public override string FormatType => "json2";
    }
}