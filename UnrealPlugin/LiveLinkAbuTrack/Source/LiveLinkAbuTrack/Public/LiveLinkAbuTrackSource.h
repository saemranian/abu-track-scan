#pragma once

#include "CoreMinimal.h"
#include "ILiveLinkSource.h"
#include "HAL/Runnable.h"
#include "HAL/ThreadSafeBool.h"
#include "IMessageReceiver.h"
#include "LiveLinkSourceSettings.h"
#include "UObject/WeakObjectPtr.h"
#include "AbuClockFFI.h"
#include "LiveLinkAbuTrackVersion.h"

// Standard Unreal reflection header
#include "LiveLinkAbuTrackSource.generated.h"

UCLASS()
class LIVELINKABUTRACK_API ULiveLinkAbuTrackSourceSettings : public ULiveLinkSourceSettings
{
	GENERATED_BODY()

public:
	// The UDP port used to listen for tracking packets from Abu Track (iOS / Windows).
	UPROPERTY(EditAnywhere, Category = "Connection Settings", meta = (ClampMin = "1024", ClampMax = "65535"))
	int32 Port = 8080;

	// Abu Clock Master IP for ecosystem registration & timecode fallback.
	UPROPERTY(EditAnywhere, Category = "AbuClock Synchronization")
	FString AbuClockMasterHost = TEXT("127.0.0.1");

	// Abu Clock REST API port (default 7878).
	UPROPERTY(EditAnywhere, Category = "AbuClock Synchronization", meta = (ClampMin = "1024", ClampMax = "65535"))
	int32 AbuClockRestPort = 7878;

	// Default SMPTE frame rate numerator if not specified in incoming packet.
	UPROPERTY(EditAnywhere, Category = "AbuClock Synchronization")
	int32 FrameRateNumerator = 30000;

	// Default SMPTE frame rate denominator if not specified in incoming packet.
	UPROPERTY(EditAnywhere, Category = "AbuClock Synchronization")
	int32 FrameRateDenominator = 1001;

	// Default SMPTE drop-frame flag if not specified in incoming packet.
	UPROPERTY(EditAnywhere, Category = "AbuClock Synchronization")
	bool bDropFrame = true;

	// Override focal length if live focal length streaming is disabled.
	UPROPERTY(EditAnywhere, Category = "Camera Calibration", meta = (ClampMin = "1.0", ClampMax = "1000.0"))
	float FocalLengthOverride = 24.0f;

	// Toggle whether to use the live focal length streamed from the iOS device or manual override.
	UPROPERTY(EditAnywhere, Category = "Camera Calibration")
	bool bUseLiveFocalLength = true;

	// Live focal length received from the iOS device (in millimeters).
	UPROPERTY(VisibleAnywhere, Category = "Camera Calibration")
	float LiveFocalLength = 24.0f;

	// Radial lens distortion parameter K1 received from the iOS device.
	UPROPERTY(VisibleAnywhere, Category = "Camera Calibration")
	float K1 = 0.0f;

	// Radial lens distortion parameter K2 received from the iOS device.
	UPROPERTY(VisibleAnywhere, Category = "Camera Calibration")
	float K2 = 0.0f;

	// Detected wire protocol (Enriched JSON, FreeD 0xD1, SMPTE FreeD-TC 0xD2, OpenTrackIO OTrk).
	UPROPERTY(VisibleAnywhere, Category = "AbuClock Diagnostics")
	FString ActiveProtocol = TEXT("Waiting...");

	// Live SMPTE ST 12-1 / ST 2059-2 timecode string stamped onto SceneTime.
	UPROPERTY(VisibleAnywhere, Category = "AbuClock Diagnostics")
	FString LiveSmpteTimecode = TEXT("00:00:00;00.00");

	// Live 32-bit BCD timecode hex word.
	UPROPERTY(VisibleAnywhere, Category = "AbuClock Diagnostics")
	FString LiveBcdTimecodeHex = TEXT("0x00000000");

	// Live 64-bit TAI nanosecond optical exposure midpoint timestamp.
	UPROPERTY(VisibleAnywhere, Category = "AbuClock Diagnostics")
	int64 LiveTaiNanoseconds = 0;

	// Continuous sub-frame phase [0.0, 1.0) within the current video frame.
	UPROPERTY(VisibleAnywhere, Category = "AbuClock Diagnostics")
	float LiveSubframePhase = 0.0f;

	// Sender clock lock state (LOCKED_MASTER, FIELD_MASTER, HOLDOVER, etc.).
	UPROPERTY(VisibleAnywhere, Category = "AbuClock Diagnostics")
	FString ClockLockState = TEXT("UNKNOWN");
};

class FSocket;
class FRunnableThread;

class LIVELINKABUTRACK_API FLiveLinkAbuTrackSource : public ILiveLinkSource, public FRunnable
{
public:
	FLiveLinkAbuTrackSource(int32 InPort);
	virtual ~FLiveLinkAbuTrackSource() override;

	// ILiveLinkSource interface
	virtual void ReceiveClient(ILiveLinkClient* InClient, FGuid InSourceGuid) override;
	virtual bool IsSourceStillValid() const override;
	virtual bool RequestSourceShutdown() override;
	virtual void InitializeSettings(ULiveLinkSourceSettings* Settings) override;
	virtual TSubclassOf<ULiveLinkSourceSettings> GetSettingsClass() const override;
	
	virtual FText GetSourceType() const override;
	virtual FText GetSourceMachineName() const override;
	virtual FText GetSourceStatus() const override;

	// FRunnable interface (receiver thread)
	virtual uint32 Run() override;
	virtual void Stop() override;
	virtual void Exit() override;

private:
	void StartReceiverThread();
	void StopReceiverThread();

	void ProcessRawDatagram(const uint8* Data, int32 Size);
	void ProcessJsonPacket(const FString& PacketData, const FString& ProtocolLabel);
	void ProcessFreeDPacket(const uint8* Data, int32 Size);
	void ProcessOpenTrackIOPacket(const uint8* Data, int32 Size);

	void PushSynchronizedCameraFrame(
		double XCm,
		double YCm,
		double ZCm,
		double PitchDeg,
		double YawDeg,
		double RollDeg,
		double FocalLengthMm,
		double FocusDistanceCm,
		double K1Val,
		double K2Val,
		uint64 TaiNs,
		uint32 BcdTimecode,
		const FString& SmpteString,
		double SubframePhase,
		int32 FpsNum,
		int32 FpsDen,
		bool bDropFrame,
		const FString& LockState,
		const FString& ProtocolLabel
	);

	static int32 UnpackFreeD24(const uint8* Bytes3);
	static uint32 ReadUInt32BE(const uint8* Bytes4);
	static uint64 ReadUInt64BE(const uint8* Bytes8);

	// Core state
	ILiveLinkClient* LiveLinkClient;
	FGuid SourceGuid;
	int32 UDPPort;
	
	FSocket* Socket;
	FRunnableThread* Thread;
	FThreadSafeBool bIsRunning;
	
	FName SubjectName;
	bool bSubjectRegistered;

	TWeakObjectPtr<ULiveLinkAbuTrackSourceSettings> SavedSettings;
};
