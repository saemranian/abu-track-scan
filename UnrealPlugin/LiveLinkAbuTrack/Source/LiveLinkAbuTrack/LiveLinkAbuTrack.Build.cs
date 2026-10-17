using UnrealBuildTool;

public class LiveLinkAbuTrack : ModuleRules
{
	public LiveLinkAbuTrack(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = ModuleRules.PCHUsageMode.UseExplicitOrSharedPCHs;
		
		PublicIncludePaths.AddRange(
			new string[] {
				// Add public include paths here
			}
		);
				
		PrivateIncludePaths.AddRange(
			new string[] {
				// Add private include paths here
			}
		);
			
		PublicDependencyModuleNames.AddRange(
			new string[]
			{
				"Core",
				"LiveLinkInterface",
				"TimeManagement",
				"Messaging",
				"Networking",
				"Sockets"
			}
		);
			
		PrivateDependencyModuleNames.AddRange(
			new string[]
			{
				"CoreUObject",
				"Engine",
				"InputCore",
				"Slate",
				"SlateCore",
				"Json",
				"HTTP"
			}
		);
		
		DynamicallyLoadedModuleNames.AddRange(
			new string[]
			{
				// Add dynamically loaded modules here
			}
		);
	}
}
