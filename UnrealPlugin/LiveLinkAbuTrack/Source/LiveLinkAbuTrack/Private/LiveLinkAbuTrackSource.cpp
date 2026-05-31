#include "LiveLinkAbuTrackSource.h"
#include "Common/UdpSocketBuilder.h"
#include "Sockets.h"
#include "SocketSubsystem.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonReader.h"
#include "Roles/LiveLinkCameraRole.h"
#include "Roles/LiveLinkCameraTypes.h"
#include "HAL/RunnableThread.h"
#include "Misc/ScopeLock.h"
#include "ILiveLinkClient.h"

FLiveLinkAbuTrackSource::FLiveLinkAbuTrackSource(int32 InPort)
	: LiveLinkClient(nullptr)
	, UDPPort(InPort)
	, Socket(nullptr)
	, Thread(nullptr)
	, bIsRunning(false)
	, SubjectName(TEXT("AbuTrack"))
	, bSubjectRegistered(false)
{
	StartReceiverThread();
}

FLiveLinkAbuTrackSource::~FLiveLinkAbuTrackSource()
{
	StopReceiverThread();
}

void FLiveLinkAbuTrackSource::ReceiveClient(ILiveLinkClient* InClient, FGuid InSourceGuid)
{
	LiveLinkClient = InClient;
	SourceGuid = InSourceGuid;
}

bool FLiveLinkAbuTrackSource::IsSourceStillValid() const
{
	return bIsRunning;
}

bool FLiveLinkAbuTrackSource::RequestSettingsApply(ULiveLinkSourceSettings* Settings)
{
	return true;
}

void FLiveLinkAbuTrackSource::InitializeSettings(ULiveLinkSourceSettings* Settings)
{
}

TSubclassOf<ULiveLinkSourceSettings> FLiveLinkAbuTrackSource::GetSettingsClass() const
{
	return ULiveLinkSourceSettings::StaticClass();
}

FText FLiveLinkAbuTrackSource::GetSourceType() const
{
	return FText::FromString(TEXT("Abu Track Live Receiver"));
}

FText FLiveLinkAbuTrackSource::GetSourceMachineName() const
{
	return FText::FromString(FPlatformProcess::ComputerName());
}

FText FLiveLinkAbuTrackSource::GetSourceStatus() const
{
	return bIsRunning ? FText::FromString(TEXT("Active")) : FText::FromString(TEXT("Disconnected"));
}

void FLiveLinkAbuTrackSource::StartReceiverThread()
{
	bIsRunning = true;
	
	// Bind socket with SO_REUSEADDR enabled
	Socket = FUdpSocketBuilder(TEXT("AbuTrackUDPSocket"))
		.BoundToPort(UDPPort)
		.AsNonBlocking()
		.WithReceiveBufferSize(64 * 1024)
		.WithMulticastLoopback()
		.AsReusable();

	if (Socket)
	{
		Thread = FRunnableThread::Create(this, TEXT("AbuTrackReceiverThread"), 0, TPri_AboveNormal);
	}
	else
	{
		bIsRunning = false;
	}
}

void FLiveLinkAbuTrackSource::StopReceiverThread()
{
	bIsRunning = false;
	if (Thread)
	{
		Thread->WaitForCompletion();
		delete Thread;
		Thread = nullptr;
	}
	if (Socket)
	{
		ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM)->DestroySocket(Socket);
		Socket = nullptr;
	}
}

uint32 FLiveLinkAbuTrackSource::Run()
{
	TSharedRef<FInternetAddr> SenderAddr = ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM)->CreateInternetAddr();
	TArray<uint8> RecvBuffer;
	RecvBuffer.SetNumUninitialized(4096);

	while (bIsRunning)
	{
		uint32 Size = 0;
		if (Socket->HasPendingData(Size))
		{
			int32 Read = 0;
			if (Socket->RecvFrom(RecvBuffer.GetData(), RecvBuffer.Num(), Read, *SenderAddr))
			{
				if (Read > 0)
				{
					FString PacketData = FString(UTF8_TO_TCHAR(reinterpret_cast<const char*>(RecvBuffer.GetData())), Read);
					ProcessPacket(PacketData);
				}
			}
		}
		FPlatformProcess::Sleep(0.001f); // Sleep 1ms to minimize CPU usage
	}

	return 0;
}

void FLiveLinkAbuTrackSource::Stop()
{
	bIsRunning = false;
}

void FLiveLinkAbuTrackSource::Exit()
{
}

void FLiveLinkAbuTrackSource::ProcessPacket(const FString& PacketData)
{
	if (!LiveLinkClient)
	{
		return;
	}

	TSharedPtr<FJsonObject> JsonObject;
	TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(PacketData);

	if (FJsonSerializer::Deserialize(Reader, JsonObject) && JsonObject.IsValid())
	{
		TArray<TSharedPtr<FJsonValue>> TranslationArray = JsonObject->GetArrayField(TEXT("translation"));
		TArray<TSharedPtr<FJsonValue>> RotationArray = JsonObject->GetArrayField(TEXT("rotation"));

		if (TranslationArray.Num() >= 3 && RotationArray.Num() >= 3)
		{
			// Extract translations (meters to centimeters in Unreal Engine)
			double X = TranslationArray[0]->AsNumber() * 100.0;
			double Y = TranslationArray[1]->AsNumber() * 100.0;
			double Z = TranslationArray[2]->AsNumber() * 100.0;

			// Extract rotations (Pitch, Yaw, Roll in degrees)
			double Pitch = RotationArray[0]->AsNumber();
			double Yaw = RotationArray[1]->AsNumber();
			double Roll = RotationArray[2]->AsNumber();

			double Timestamp = JsonObject->GetNumberField(TEXT("timestamp"));

			// Register subject if not already done
			if (!bSubjectRegistered)
			{
				FLiveLinkStaticDataStruct StaticData(FLiveLinkCameraStaticData::StaticStruct());
				FLiveLinkCameraStaticData& CameraStaticData = *StaticData.Cast<FLiveLinkCameraStaticData>();
				CameraStaticData.bIsRotationSupported = true;
				CameraStaticData.bIsLocationSupported = true;
				CameraStaticData.bIsFocalLengthSupported = true;
				CameraStaticData.bIsFocusDistanceSupported = true;
				CameraStaticData.bIsApertureSupported = true;
 
				LiveLinkClient->PushSubjectStaticData_AnyThread({ SourceGuid, SubjectName }, ULiveLinkCameraRole::StaticClass(), MoveTemp(StaticData));
				bSubjectRegistered = true;
			}

			// Push frame data
			FLiveLinkFrameDataStruct FrameData(FLiveLinkCameraFrameData::StaticStruct());
			FLiveLinkCameraFrameData& CameraFrameData = *FrameData.Cast<FLiveLinkCameraFrameData>();
			
			// Build Unreal Transform coordinate
			CameraFrameData.Transform = FTransform(FRotator(Pitch, Yaw, Roll), FVector(X, Y, Z));
			CameraFrameData.FocalLength = JsonObject->GetNumberField(TEXT("focalLength"));
			CameraFrameData.WorldTime = FLiveLinkWorldTime(Timestamp);

			LiveLinkClient->PushSubjectFrameData_AnyThread({ SourceGuid, SubjectName }, MoveTemp(FrameData));
		}
	}
}
