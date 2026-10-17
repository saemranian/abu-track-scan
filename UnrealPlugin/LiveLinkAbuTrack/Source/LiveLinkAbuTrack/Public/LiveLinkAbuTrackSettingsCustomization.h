#pragma once

#if WITH_EDITOR

#include "CoreMinimal.h"
#include "IDetailCustomization.h"
#include "Input/Reply.h"
#include "UObject/WeakObjectPtr.h"

class IDetailLayoutBuilder;
class ULiveLinkAbuTrackSourceSettings;

/**
 * FLiveLinkAbuTrackSettingsCustomization
 *
 * Custom Slate Details Panel header for ULiveLinkAbuTrackSourceSettings in the Unreal Engine 5
 * Live Link panel. Renders:
 *  - Live Abu Clock SMPTE ST 12-1 / ST 2059-2 Timecode HUD banner + sub-frame phase progress bar
 *  - Active wire protocol & clock lock badge
 *  - 1-Click "[Configure UE5 TimecodeProvider & Genlock]" button
 *  - Collapsible Quick Start Virtual Production Setup Guide
 */
class FLiveLinkAbuTrackSettingsCustomization : public IDetailCustomization
{
public:
	static TSharedRef<IDetailCustomization> MakeInstance();

	// IDetailCustomization interface
	virtual void CustomizeDetails(IDetailLayoutBuilder& DetailBuilder) override;

private:
	FReply OnConfigureEngineTimecodeClicked();
	FText GetLiveTimecodeText() const;
	FText GetProtocolAndLockText() const;
	TOptional<float> GetSubframePhaseValue() const;

	TWeakObjectPtr<ULiveLinkAbuTrackSourceSettings> EditingSettings;
};

#endif // WITH_EDITOR
