// Copyright Antigravity. All Rights Reserved.

#include "Modules/ModuleManager.h"
#include "LiveLinkAbuTrackSource.h"

#if WITH_EDITOR
#include "PropertyEditorModule.h"
#include "LiveLinkAbuTrackSettingsCustomization.h"
#endif

class FLiveLinkAbuTrackModule : public IModuleInterface
{
public:
	virtual void StartupModule() override
	{
#if WITH_EDITOR
		FPropertyEditorModule& PropertyModule = FModuleManager::LoadModuleChecked<FPropertyEditorModule>("PropertyEditor");
		PropertyModule.RegisterCustomClassLayout(
			ULiveLinkAbuTrackSourceSettings::StaticClass()->GetFName(),
			FOnGetDetailCustomizationInstance::CreateStatic(&FLiveLinkAbuTrackSettingsCustomization::MakeInstance)
		);
		PropertyModule.NotifyCustomizationModuleChanged();
#endif
	}

	virtual void ShutdownModule() override
	{
#if WITH_EDITOR
		if (FModuleManager::Get().IsModuleLoaded("PropertyEditor"))
		{
			FPropertyEditorModule& PropertyModule = FModuleManager::GetModuleChecked<FPropertyEditorModule>("PropertyEditor");
			PropertyModule.UnregisterCustomClassLayout(ULiveLinkAbuTrackSourceSettings::StaticClass()->GetFName());
		}
#endif
	}
};

IMPLEMENT_MODULE(FLiveLinkAbuTrackModule, LiveLinkAbuTrack)
