// CREST Phase P.1 (audit follow-up to H4): the ImplementationLoaderSubModule
// class previously lived here. It was the dynamic-loading SubModule from
// upstream ButterLib's pattern where Bannerlord.ButterLib.Implementation.*.dll
// files were discovered in the bin folder by reflection.
//
// Phase H replaced that with a direct SubModule.xml entry pointing at
// Crest.ButterLib.Implementation.SubModule, so this class became dead code
// after the rebrand. Phase P.1 retired it entirely.
//
// File kept (empty) instead of deleted so existing csproj <Compile> items
// don't need updating. Future cleanup can drop the file once we audit the
// project's <ItemGroup> for unused includes.
