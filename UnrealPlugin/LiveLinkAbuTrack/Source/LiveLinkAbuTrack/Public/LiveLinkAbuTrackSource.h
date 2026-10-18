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
	UPROPERTY(EditAnywhere, Category = "01 | Connection Settings", meta = (
		DisplayName = "UDP Telemetry Port",
		ToolTip = "Local UDP port to receive 6DoF camera tracking packets from Abu Track & Scan (default: 8080 direct from iOS, or 8081 forwarded from Desktop Workstation).",
		ClampMin = "1024", ClampMax = "65535"))
	int32 Port = 8080;

	// Abu Clock Master IP for ecosystem registration & timecode fallback.
	UPROPERTY(EditAnywhere, Category = "02 | AbuClock ST 2059 Sync", meta = (
		DisplayName = "Abu Clock Master IP",
		ToolTip = "IPv4 address of the Abu Clock Master node (use 127.0.0.1 if the Abu Track Desktop Workstation or Abu Clock daemon runs on this PC)."))
	FString AbuClockMasterHost = TEXT("127.0.0.1");

	// Abu Clock REST API port (default 7878).
	UPROPERTY(EditAnywhere, Category = "02 | AbuClock ST 2059 Sync", meta = (
		DisplayName = "Abu Clock REST Port",
		ToolTip = "HTTP REST control port of the Abu Clock Master daemon (default: 7878).",
		ClampMin = "1024", ClampMax = "65535"))
	int32 AbuClockRestPort = 7878;

	// Default SMPTE frame rate numerator if not specified in incoming packet.
	UPROPERTY(EditAnywhere, Category = "02 | AbuClock ST 2059 Sync", meta = (
		DisplayName = "SMPTE Frame Rate Numerator",
		ToolTip = "Nominal frame rate numerator (e.g. 24000 for 23.976, 24 for 24fps, 25 for 25fps, 30000 for 29.97, 30 for 30fps, 60 for 60fps)."))
	int32 FrameRateNumerator = 30000;

	// Default SMPTE frame rate denominator if not specified in incoming packet.
	UPROPERTY(EditAnywhere, Category = "02 | AbuClock ST 2059 Sync", meta = (
		DisplayName = "SMPTE Frame Rate Denominator",
		ToolTip = "Nominal frame rate denominator (use 1001 for NTSC fractional rates like 23.976 / 29.97 / 59.94, or 1 for integer rates)."))
	int32 FrameRateDenominator = 1001;

	// Default SMPTE drop-frame flag if not specified in incoming packet.
	UPROPERTY(EditAnywhere, Category = "02 | AbuClock ST 2059 Sync", meta = (
		DisplayName = "SMPTE Drop-Frame (;)",
		ToolTip = "Enable SMPTE ST 12-1 Drop-Frame counting (; separator) for 29.97 DF and 59.94 DF studio workflows."))
	bool bDropFrame = true;

	// Override focal length if live focal length streaming is disabled.
	UPROPERTY(EditAnywhere, Category = "03 | Camera & Lens Calibration", meta = (
		DisplayName = "Manual Focal Length Override (mm)",
		ToolTip = "Fallback 35mm-equivalent or physical focal length (in mm) applied to the CineCamera when 'Use Live Streamed Focal Length' is unchecked.",
		ClampMin = "1.0", ClampMax = "1000.0", EditCondition = "!bUseLiveFocalLength"))
	float FocalLengthOverride = 24.0f;

	// Toggle whether to use the live focal length streamed from the iOS device or manual override.
	UPROPERTY(EditAnywhere, Category = "03 | Camera & Lens Calibration", meta = (
		DisplayName = "Use Live Streamed Focal Length",
		ToolTip = "When enabled, dynamically drives the CineCamera focal length from the live optical intrinsics streamed by the iOS/Workstation rig."))
	bool bUseLiveFocalLength = true;

	// Live focal length received from the iOS device (in millimeters).
	UPROPERTY(VisibleAnywhere, Category = "03 | Camera & Lens Calibration", meta = (
		DisplayName = "Live Focal Length (mm)",
		ToolTip = "Real-time focal length (in millimeters) unpacked from the active telemetry stream."))
	float LiveFocalLength = 24.0f;

	// Radial lens distortion parameter K1 received from the iOS device.
	UPROPERTY(VisibleAnywhere, Category = "03 | Camera & Lens Calibration", meta = (
		DisplayName = "Radial Distortion K1",
		ToolTip = "Real-time Brown-Conrady primary radial distortion coefficient K1 received from the calibrated lens profile."))
	float K1 = 0.0f;

	// Radial lens distortion parameter K2 received from the iOS device.
	UPROPERTY(VisibleAnywhere, Category = "03 | Camera & Lens Calibration", meta = (
		DisplayName = "Radial Distortion K2",
		ToolTip = "Real-time Brown-Conrady secondary radial distortion coefficient K2 received from the calibrated lens profile."))
	float K2 = 0.0f;

	// Detected wire protocol (Enriched JSON, FreeD 0xD1, SMPTE FreeD-TC 0xD2, OpenTrackIO OTrk).
	UPROPERTY(VisibleAnywhere, Category = "04 | Live Telemetry Diagnostics", meta = (
		DisplayName = "Detected Wire Protocol",
		ToolTip = "Automatically detected packet format: Enriched JSON, FreeD 0xD1 (29B), FreeD-TC 0xD2 (37B/41B), or OpenTrackIO (OTrk)."))
	FString ActiveProtocol = TEXT("Waiting...");

	// Live SMPTE ST 12-1 / ST 2059-2 timecode string stamped onto SceneTime.
	UPROPERTY(VisibleAnywhere, Category = "04 | Live Telemetry Diagnostics", meta = (
		DisplayName = "Live SMPTE Timecode",
		ToolTip = "Frame-accurate SMPTE ST 12-1 / ST 2059-2 timecode stamped onto every Live Link FrameData.SceneTime."))
	FString LiveSmpteTimecode = TEXT("00:00:00;00.00");

	// Live 32-bit BCD timecode hex word.
	UPROPERTY(VisibleAnywhere, Category = "04 | Live Telemetry Diagnostics", meta = (
		DisplayName = "32-bit BCD Timecode Word",
		ToolTip = "Raw 32-bit Binary-Coded Decimal (BCD) SMPTE timecode word unpacked from the telemetry header."))
	FString LiveBcdTimecodeHex = TEXT("0x00000000");

	// Live 64-bit TAI nanosecond optical exposure midpoint timestamp.
	UPROPERTY(VisibleAnywhere, Category = "04 | Live Telemetry Diagnostics", meta = (
		DisplayName = "Optical Exposure TAI (ns)",
		ToolTip = "64-bit IEEE 1588 / PTP TAI nanosecond timestamp captured at the exact midpoint of the camera sensor exposure."))
	int64 LiveTaiNanoseconds = 0;

	// Continuous sub-frame phase [0.0, 1.0) within the current video frame.
	UPROPERTY(VisibleAnywhere, Category = "04 | Live Telemetry Diagnostics", meta = (
		DisplayName = "Sub-Frame Phase [0..1)",
		ToolTip = "Continuous sub-frame phase progress (0.0 to 1.0) within the current SMPTE frame interval."))
	float LiveSubframePhase = 0.0f;

	// Sender clock lock state (LOCKED_MASTER, FIELD_MASTER, HOLDOVER, etc.).
	UPROPERTY(VisibleAnywhere, Category = "04 | Live Telemetry Diagnostics", meta = (
		DisplayName = "Abu Clock Lock State",
		ToolTip = "Synchronization lock status reported by the sender's Abu Clock engine (LOCKED, MASTER, HOLDOVER, or FREERUN)."))
	FString ClockLockState = TEXT("UNKNOWN");

	// Total UDP telemetry packets received since source creation.
	UPROPERTY(VisibleAnywhere, Category = "04 | Live Telemetry Diagnostics", meta = (
		DisplayName = "Received UDP Packets",
		ToolTip = "Total valid 6DoF telemetry packets received on the configured UDP port."))
	int64 ReceivedPacketCount = 0;

	// Indicates whether upstream lever-arm / origin / pitch offsets were already applied by iOS or Desktop Workstation.
	UPROPERTY(VisibleAnywhere, Category = "04 | Live Telemetry Diagnostics", meta = (
		DisplayName = "Upstream Offsets Applied",
		ToolTip = "True when incoming telemetry packets already carry Lever-Arm, World Origin, or Pitch Offset compensation from iOS or Desktop Workstation."))
	bool bUpstreamOffsetsApplied = false;

	// Non-serialized runtime heartbeat timestamp (FPlatformTime::Seconds) and Genlock status
	double LastPacketWallTimeSec = 0.0;
	bool bEngineGenlockConfigured = false;

	/**
	 * 1-Click helper that instantiates and assigns UAbuClockTimecodeProvider and
	 * UAbuClockCustomTimeStep onto GEngine so Unreal Engine's master Timecode & Genlock
	 * match this Live Link source without manual Project Settings navigation.
	 */
	UFUNCTION(CallInEditor, Category = "02 | AbuClock ST 2059 Sync", meta = (
		DisplayName = "Configure UE5 TimecodeProvider & Genlock",
		ToolTip = "Automatically configures Unreal Engine's global TimecodeProvider (UAbuClockTimecodeProvider) and Genlock CustomTimeStep (UAbuClockCustomTimeStep) to match this source."))
	void ConfigureEngineTimecodeAndGenlock();
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
		const FString& ProtocolLabel,
		bool bOffsetsApplied = false
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
	TAtomic<int64> TotalReceivedPackets;
	TAtomic<double> LastPacketPlatformSeconds;

	TWeakObjectPtr<ULiveLinkAbuTrackSourceSettings> SavedSettings;
};
