using MCM.Abstractions.Base.PerCampaign;

namespace MCM.Tests
{
    public abstract class BaseTestPerCampaignSettingsBase<T> : AttributePerCampaignSettings<T> where T : PerCampaignSettings, new()
    {
        public override string FolderName => "MCM.Tests";
    }
}