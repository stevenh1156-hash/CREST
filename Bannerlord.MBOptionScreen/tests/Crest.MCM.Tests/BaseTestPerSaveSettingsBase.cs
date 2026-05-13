using MCM.Abstractions.Base.PerSave;

namespace MCM.Tests
{
    public abstract class BaseTestPerSaveSettingsBase<T> : AttributePerSaveSettings<T> where T : PerSaveSettings, new()
    {
        public override string FolderName => "MCM.Tests";
    }
}