#include "LiveLinkAbuTrackSourceFactory.h"
#include "LiveLinkAbuTrackSource.h"
#include "Localization/Localization.h"

#define LOCTEXT_NAMESPACE "LiveLinkAbuTrackSourceFactory"

FText ULiveLinkAbuTrackSourceFactory::GetSourceDisplayName() const
{
	return LOCTEXT("SourceDisplayName", "Abu Track Source");
}

FText ULiveLinkAbuTrackSourceFactory::GetSourceTooltip() const
{
	return LOCTEXT("SourceTooltip", "Listen for live high-precision geodetic tracking poses from Abu Track iOS app on UDP port.");
}

ULiveLinkAbuTrackSourceFactory::EMenuType ULiveLinkAbuTrackSourceFactory::GetMenuType() const
{
	return EMenuType::MenuEntry;
}

TSharedPtr<ILiveLinkSource> ULiveLinkAbuTrackSourceFactory::CreateSource(const FString& ConnectionString) const
{
	// ConnectionString is standard target port, default to "8080"
	int32 Port = 8080;
	if (!ConnectionString.IsEmpty())
	{
		Port = FCString::Atoi(*ConnectionString);
	}
	
	return MakeShared<FLiveLinkAbuTrackSource>(Port);
}

#undef LOCTEXT_NAMESPACE
