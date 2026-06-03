#pragma once

#include "CoreMinimal.h"
#include "ILiveLinkSource.h"
#include "HAL/Runnable.h"
#include "HAL/ThreadSafeBool.h"
#include "IMessageReceiver.h"
#include "LiveLinkSourceSettings.h"
#include "UObject/WeakObjectPtr.h"

// Standard Unreal reflection header
#include "LiveLinkAbuTrackSource.generated.h"

UCLASS()
class LIVELINKABUTRACK_API ULiveLinkAbuTrackSourceSettings : public ULiveLinkSourceSettings
{
	GENERATED_BODY()

public:
	// The UDP port used to listen for tracking packets from the iOS app.
	UPROPERTY(EditAnywhere, Category = "Connection Settings", meta = (ClampMin = "1024", ClampMax = "65535"))
	int32 Port = 8080;

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
	void ProcessPacket(const FString& PacketData);

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
