#pragma once

#include "CoreMinimal.h"
#include "ILiveLinkSource.h"
#include "HAL/Runnable.h"
#include "HAL/ThreadSafeBool.h"
#include "IMessageReceiver.h"
#include "LiveLinkSourceSettings.h"

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
};
