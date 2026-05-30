#pragma once

#include "CoreMinimal.h"
#include "LiveLinkSourceFactory.h"
#include "LiveLinkAbuTrackSourceFactory.generated.class.h" // Wait, standard Unreal uses .generated.h

// Standard Unreal reflection header
#include "LiveLinkAbuTrackSourceFactory.generated.h"

UCLASS()
class LIVELINKABUTRACK_API ULiveLinkAbuTrackSourceFactory : public ULiveLinkSourceFactory
{
	GENERATED_BODY()

public:
	virtual FText GetSourceDisplayName() const override;
	virtual FText GetSourceTooltip() const override;
	
	virtual EMenuType GetMenuType() const override;
	virtual TSharedPtr<ILiveLinkSource> CreateSource(const FString& ConnectionString) const override;
};
