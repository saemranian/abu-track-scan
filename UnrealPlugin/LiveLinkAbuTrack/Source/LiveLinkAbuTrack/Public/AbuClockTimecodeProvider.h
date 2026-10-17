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
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "AbuClock", meta = (
		DisplayName = "SMPTE Frame Rate Numerator",
		ToolTip = "Target SMPTE frame rate numerator (e.g. 24000, 24, 25, 30000, 30, 60)."))
	int32 FrameRateNumerator = 30000;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "AbuClock", meta = (
		DisplayName = "SMPTE Frame Rate Denominator",
		ToolTip = "Target SMPTE frame rate denominator (1001 for fractional NTSC rates, 1 for integer rates)."))
	int32 FrameRateDenominator = 1001;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "AbuClock", meta = (
		DisplayName = "SMPTE Drop-Frame (;)",
		ToolTip = "Use SMPTE ST 12-1 Drop-Frame frame-number skipping for 29.97 DF and 59.94 DF."))
	bool bDropFrame = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "AbuClock", meta = (
		DisplayName = "PTP / CSPTP Domain (0-127)",
		ToolTip = "IEEE 1588 / SMPTE ST 2059-2 PTP domain number (default: 0).",
		ClampMin = "0", ClampMax = "127"))
	int32 PtpDomain = 0;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "AbuClock|Diagnostics", meta = (
		DisplayName = "Last Synthesized SMPTE Timecode",
		ToolTip = "Most recent SMPTE timecode string synthesized from the Abu Clock OverlayClock."))
	FString LastSmpteTimecode = TEXT("00:00:00;00.00");

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "AbuClock|Diagnostics", meta = (
		DisplayName = "Last TAI Timestamp (ns)",
		ToolTip = "Most recent 64-bit TAI nanosecond epoch timestamp read from Abu Clock."))
	int64 LastTaiNanoseconds = 0;

	virtual bool FetchTimecode(FQualifiedFrameTime& OutFrameTime) override;
	virtual ETimecodeProviderSynchronizationState GetSynchronizationState() const override;
	virtual bool Initialize(class UEngine* InEngine) override;
	virtual void Shutdown(class UEngine* InEngine) override;

private:
	AbuClockOpaqueHandle* NativeClockHandle = nullptr;
	ETimecodeProviderSynchronizationState SyncState = ETimecodeProviderSynchronizationState::Closed;
};
