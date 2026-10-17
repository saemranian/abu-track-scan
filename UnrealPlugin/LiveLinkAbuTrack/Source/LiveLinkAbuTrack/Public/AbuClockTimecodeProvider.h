#pragma once

#include "CoreMinimal.h"
#include "Engine/TimecodeProvider.h"
#include "Misc/QualifiedFrameTime.h"
#include "AbuClockFFI.h"
#include "AbuClockTimecodeProvider.generated.h"

/**
 * UAbuClockTimecodeProvider
 *
 * Stamps Unreal Engine 5's global timecode and TimecodeSynchronizer directly from
 * Abu Clock's disciplined OverlayClock (SMPTE ST 2059-2 / ST 12-1) with sub-frame phase.
 */
UCLASS(Blueprintable, EditInlineNew, meta = (DisplayName = "Abu Clock SMPTE ST 2059 Timecode Provider"))
class LIVELINKABUTRACK_API UAbuClockTimecodeProvider : public UTimecodeProvider
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "AbuClock")
	int32 FrameRateNumerator = 30000;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "AbuClock")
	int32 FrameRateDenominator = 1001;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "AbuClock")
	bool bDropFrame = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "AbuClock")
	int32 PtpDomain = 0;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "AbuClock|Diagnostics")
	FString LastSmpteTimecode = TEXT("00:00:00;00.00");

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "AbuClock|Diagnostics")
	int64 LastTaiNanoseconds = 0;

	virtual bool FetchTimecode(FQualifiedFrameTime& OutFrameTime) override;
	virtual ETimecodeProviderSynchronizationState GetSynchronizationState() const override;
	virtual bool Initialize(class UEngine* InEngine) override;
	virtual void Shutdown(class UEngine* InEngine) override;

private:
	AbuClockOpaqueHandle* NativeClockHandle = nullptr;
	ETimecodeProviderSynchronizationState SyncState = ETimecodeProviderSynchronizationState::Closed;
};
