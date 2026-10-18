#include "LiveLinkAbuTrackSource.h"
#include "AbuClockTimecodeProvider.h"
#include "AbuClockCustomTimeStep.h"
#include "Engine/Engine.h"
#include "Common/UdpSocketBuilder.h"
#include "Sockets.h"
#include "SocketSubsystem.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonReader.h"
#include "Roles/LiveLinkCameraRole.h"
#include "Roles/LiveLinkCameraTypes.h"
#include "HAL/RunnableThread.h"
#include "Misc/ScopeLock.h"
#include "Misc/Timecode.h"
#include "Misc/FrameRate.h"
#include "Misc/QualifiedFrameTime.h"
#include "ILiveLinkClient.h"
#include "Async/Async.h"

void ULiveLinkAbuTrackSourceSettings::ConfigureEngineTimecodeAndGenlock()
{
	if (!GEngine)
	{
		return;
	}

	UAbuClockTimecodeProvider* TimecodeProvider = NewObject<UAbuClockTimecodeProvider>(GEngine);
	if (TimecodeProvider)
	{
		TimecodeProvider->FrameRateNumerator = FMath::Max(1, FrameRateNumerator);
		TimecodeProvider->FrameRateDenominator = FMath::Max(1, FrameRateDenominator);
		TimecodeProvider->bDropFrame = bDropFrame;
		GEngine->SetTimecodeProvider(TimecodeProvider);
	}

	UAbuClockCustomTimeStep* CustomTimeStep = NewObject<UAbuClockCustomTimeStep>(GEngine);
	if (CustomTimeStep)
	{
		CustomTimeStep->TargetFrameRate = FFrameRate(FMath::Max(1, FrameRateNumerator), FMath::Max(1, FrameRateDenominator));
		CustomTimeStep->bDropFrame = bDropFrame;
		GEngine->SetCustomTimeStep(CustomTimeStep);
	}

	bEngineGenlockConfigured = true;

	UE_LOG(LogTemp, Log, TEXT("[AbuTrack] 1-Click Configured UE5 TimecodeProvider & CustomTimeStep (%d/%d, DF=%d)"),
		FrameRateNumerator, FrameRateDenominator, bDropFrame ? 1 : 0);
}

FLiveLinkAbuTrackSource::FLiveLinkAbuTrackSource(int32 InPort)
	: LiveLinkClient(nullptr)
	, UDPPort(InPort)
	, Socket(nullptr)
	, Thread(nullptr)
	, bIsRunning(false)
	, SubjectName(TEXT("AbuTrack"))
	, bSubjectRegistered(false)
	, TotalReceivedPackets(0)
	, LastPacketPlatformSeconds(0.0)
{
	StartReceiverThread();
	FAbuClockRuntimeBridge::Get().RegisterNodeWithAbuClock(
		TEXT("127.0.0.1"),
		7878,
		FString::Printf(TEXT("UE5-LiveLinkAbuTrack-%s"), *FPlatformProcess::ComputerName()),
		UDPPort
	);
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

bool FLiveLinkAbuTrackSource::RequestSourceShutdown()
{
	StopReceiverThread();
	return true;
}

void FLiveLinkAbuTrackSource::InitializeSettings(ULiveLinkSourceSettings* Settings)
{
	ULiveLinkAbuTrackSourceSettings* SourceSettings = Cast<ULiveLinkAbuTrackSourceSettings>(Settings);
	if (SourceSettings)
	{
		SourceSettings->Port = UDPPort;
		SavedSettings = SourceSettings;
	}
}

TSubclassOf<ULiveLinkSourceSettings> FLiveLinkAbuTrackSource::GetSettingsClass() const
{
	return ULiveLinkAbuTrackSourceSettings::StaticClass();
}

FText FLiveLinkAbuTrackSource::GetSourceType() const
{
	return FText::FromString(FString::Printf(TEXT("Abu Track & Clock Live Receiver (v%s)"), TEXT(LIVELINK_ABUTRACK_VERSION_STRING)));
}

FText FLiveLinkAbuTrackSource::GetSourceMachineName() const
{
	return FText::FromString(FPlatformProcess::ComputerName());
}

FText FLiveLinkAbuTrackSource::GetSourceStatus() const
{
	if (!bIsRunning)
	{
		return FText::FromString(TEXT("Disconnected"));
	}
	const int64 PktCount = TotalReceivedPackets.Load();
	if (PktCount == 0)
	{
		return FText::FromString(FString::Printf(TEXT("Listening on UDP %d (Waiting for Stream...)"), UDPPort));
	}
	const double ElapsedSec = FPlatformTime::Seconds() - LastPacketPlatformSeconds.Load();
	if (ElapsedSec <= 2.0)
	{
		return FText::FromString(FString::Printf(TEXT("ONLINE • Streaming (%lld pkts | SMPTE ST 2059)"), PktCount));
	}
	return FText::FromString(FString::Printf(TEXT("STALE / OFFLINE (No UDP packets for %.1fs)"), ElapsedSec));
}

void FLiveLinkAbuTrackSource::StartReceiverThread()
{
	bIsRunning = true;
	
	// Bind socket with SO_REUSEADDR and 256KB buffer for high-rate telemetry + LiDAR chunks
	Socket = FUdpSocketBuilder(TEXT("AbuTrackUDPSocket"))
		.BoundToPort(UDPPort)
		.AsNonBlocking()
		.WithReceiveBufferSize(256 * 1024)
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
	RecvBuffer.SetNumUninitialized(65536);

	while (bIsRunning)
	{
		uint32 Size = 0;
		while (Socket && Socket->HasPendingData(Size))
		{
			int32 Read = 0;
			if (Socket->RecvFrom(RecvBuffer.GetData(), RecvBuffer.Num() - 1, Read, *SenderAddr))
			{
				if (Read > 0)
				{
					RecvBuffer[Read] = 0;
					ProcessRawDatagram(RecvBuffer.GetData(), Read);
				}
			}
			else
			{
				break;
			}
		}
		FPlatformProcess::Sleep(0.0005f); // Sub-millisecond poll interval for low-latency tracking
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

int32 FLiveLinkAbuTrackSource::UnpackFreeD24(const uint8* Bytes3)
{
	int32 Val = (static_cast<int32>(Bytes3[0]) << 16) | (static_cast<int32>(Bytes3[1]) << 8) | static_cast<int32>(Bytes3[2]);
	if ((Val & 0x00800000) != 0)
	{
		Val -= 0x01000000;
	}
	return Val;
}

uint32 FLiveLinkAbuTrackSource::ReadUInt32BE(const uint8* Bytes4)
{
	return (static_cast<uint32>(Bytes4[0]) << 24)
		| (static_cast<uint32>(Bytes4[1]) << 16)
		| (static_cast<uint32>(Bytes4[2]) << 8)
		| static_cast<uint32>(Bytes4[3]);
}

uint64 FLiveLinkAbuTrackSource::ReadUInt64BE(const uint8* Bytes8)
{
	uint64 Result = 0;
	for (int32 i = 0; i < 8; ++i)
	{
		Result = (Result << 8) | static_cast<uint64>(Bytes8[i]);
	}
	return Result;
}

void FLiveLinkAbuTrackSource::ProcessRawDatagram(const uint8* Data, int32 Size)
{
	if (!LiveLinkClient || Data == nullptr || Size <= 0)
	{
		return;
	}

	// 1. Check for Binary FreeD (0xD1 = 29B/37B, 0xD2 = 41B SMPTE FreeD-TC)
	if ((Data[0] == 0xD1 && Size >= 29) || (Data[0] == 0xD2 && Size >= 41))
	{
		ProcessFreeDPacket(Data, Size);
		return;
	}

	// 2. Check for OpenTrackIO ("OTrk" 17-byte binary header + UTF-8 JSON payload)
	if (Size > 17 && Data[0] == 'O' && Data[1] == 'T' && Data[2] == 'r' && Data[3] == 'k')
	{
		ProcessOpenTrackIOPacket(Data, Size);
		return;
	}

	// 3. Default: Enriched LiveLink JSON
	FString PacketData = UTF8_TO_TCHAR(reinterpret_cast<const char*>(Data));
	ProcessJsonPacket(PacketData, TEXT("LiveLink JSON"));
}

void FLiveLinkAbuTrackSource::ProcessFreeDPacket(const uint8* Data, int32 Size)
{
	const bool bIsD2 = (Data[0] == 0xD2 && Size >= 41);
	const double PitchDeg = static_cast<double>(UnpackFreeD24(&Data[2])) / 32768.0;
	const double YawDeg = static_cast<double>(UnpackFreeD24(&Data[5])) / 32768.0;
	const double RollDeg = static_cast<double>(UnpackFreeD24(&Data[8])) / 32768.0;

	// FreeD packs PosZ, PosX, PosY in 1/64 mm -> convert to cm (divide by 640.0)
	const double ZCm = static_cast<double>(UnpackFreeD24(&Data[11])) / 640.0;
	const double XCm = static_cast<double>(UnpackFreeD24(&Data[14])) / 640.0;
	const double YCm = static_cast<double>(UnpackFreeD24(&Data[17])) / 640.0;

	const int32 ZoomRaw = UnpackFreeD24(&Data[20]);
	const int32 FocusRaw = UnpackFreeD24(&Data[23]);
	const double FocalLengthMm = (ZoomRaw > 0) ? (static_cast<double>(ZoomRaw) / 100.0) : 24.0;
	const double FocusDistanceCm = (FocusRaw > 0) ? (static_cast<double>(FocusRaw) / 10.0) : 150.0;

	int32 FpsNum = 30000;
	int32 FpsDen = 1001;
	bool bDropFrame = true;
	if (SavedSettings.IsValid())
	{
		FpsNum = SavedSettings->FrameRateNumerator;
		FpsDen = SavedSettings->FrameRateDenominator;
		bDropFrame = SavedSettings->bDropFrame;
	}

	uint64 TaiNs = 0;
	uint32 BcdTimecode = 0;
	FString SmpteString;
	double SubframePhase = 0.0;

	if (bIsD2)
	{
		BcdTimecode = ReadUInt32BE(&Data[29]);
		TaiNs = ReadUInt64BE(&Data[33]);
		bDropFrame = bDropFrame || ((BcdTimecode & (1U << 6)) != 0);

		AbuClockCFrameSnapshot Snap{};
		FAbuClockRuntimeBridge::Get().SynthesizeFromTaiNs(TaiNs, FpsNum, FpsDen, bDropFrame, Snap);
		SubframePhase = Snap.phase;

		const FTimecode DecodedTc = FAbuClockRuntimeBridge::DecodeBcdTimecode(BcdTimecode, bDropFrame);
		SmpteString = FAbuClockRuntimeBridge::FormatSmpteString(
			static_cast<uint8>(DecodedTc.Hours),
			static_cast<uint8>(DecodedTc.Minutes),
			static_cast<uint8>(DecodedTc.Seconds),
			static_cast<uint8>(DecodedTc.Frames),
			DecodedTc.bDropFrameFormat,
			SubframePhase
		);
	}
	else
	{
		if (Size >= 37)
		{
			const uint64 UtcMs = ReadUInt64BE(&Data[29]);
			TaiNs = (UtcMs * 1000000ULL) + 37000000000ULL;
		}
		else
		{
			TaiNs = FAbuClockRuntimeBridge::Get().NowTaiNanoseconds();
		}
		AbuClockCFrameSnapshot Snap{};
		FAbuClockRuntimeBridge::Get().SynthesizeFromTaiNs(TaiNs, FpsNum, FpsDen, bDropFrame, Snap);
		BcdTimecode = Snap.bcd_timecode;
		SubframePhase = Snap.phase;
		SmpteString = FAbuClockRuntimeBridge::FormatSmpteString(Snap.hours, Snap.minutes, Snap.seconds, Snap.frames, Snap.drop_frame != 0, Snap.phase);
	}

	PushSynchronizedCameraFrame(
		XCm, YCm, ZCm,
		PitchDeg, YawDeg, RollDeg,
		FocalLengthMm, FocusDistanceCm,
		0.0, 0.0,
		TaiNs, BcdTimecode, SmpteString, SubframePhase,
		FpsNum, FpsDen, bDropFrame,
		TEXT("FREED_LOCKED"),
		bIsD2 ? TEXT("FreeD-TC 0xD2 (41B)") : TEXT("FreeD 0xD1 (37B)")
	);
}

void FLiveLinkAbuTrackSource::ProcessOpenTrackIOPacket(const uint8* Data, int32 Size)
{
	const uint32 PayloadLen = ReadUInt32BE(&Data[9]);
	const int32 SafeLen = FMath::Min<int32>(Size - 17, static_cast<int32>(PayloadLen));
	if (SafeLen <= 0)
	{
		return;
	}

	TArray<uint8> JsonBytes;
	JsonBytes.Append(&Data[17], SafeLen);
	JsonBytes.Add(0);
	const FString JsonStr = UTF8_TO_TCHAR(reinterpret_cast<const char*>(JsonBytes.GetData()));

	TSharedPtr<FJsonObject> RootObj;
	TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(JsonStr);
	if (!FJsonSerializer::Deserialize(Reader, RootObj) || !RootObj.IsValid())
	{
		return;
	}

	double XCm = 0.0, YCm = 0.0, ZCm = 0.0;
	double PitchDeg = 0.0, YawDeg = 0.0, RollDeg = 0.0;

	const TArray<TSharedPtr<FJsonValue>>* TransformsArray = nullptr;
	if (RootObj->TryGetArrayField(TEXT("transforms"), TransformsArray) && TransformsArray->Num() > 0)
	{
		const TSharedPtr<FJsonObject> TransformObj = (*TransformsArray)[0]->AsObject();
		if (TransformObj.IsValid())
		{
			const TSharedPtr<FJsonObject>* TransObj = nullptr;
			if (TransformObj->TryGetObjectField(TEXT("translation"), TransObj) && TransObj->IsValid())
			{
				XCm = (*TransObj)->GetNumberField(TEXT("x")) * 100.0;
				YCm = (*TransObj)->GetNumberField(TEXT("y")) * 100.0;
				ZCm = (*TransObj)->GetNumberField(TEXT("z")) * 100.0;
			}
			const TSharedPtr<FJsonObject>* RotObj = nullptr;
			if (TransformObj->TryGetObjectField(TEXT("rotation"), RotObj) && RotObj->IsValid())
			{
				PitchDeg = (*RotObj)->GetNumberField(TEXT("pitch"));
				YawDeg = (*RotObj)->GetNumberField(TEXT("yaw"));
				RollDeg = (*RotObj)->GetNumberField(TEXT("roll"));
			}
		}
	}

	double FocalLengthMm = 24.0;
	double FocusDistanceCm = 150.0;
	double K1Val = 0.0, K2Val = 0.0;
	const TSharedPtr<FJsonObject>* LensObj = nullptr;
	if (RootObj->TryGetObjectField(TEXT("lens"), LensObj) && LensObj->IsValid())
	{
		(*LensObj)->TryGetNumberField(TEXT("focalLength"), FocalLengthMm);
		double FocusM = 1.5;
		if ((*LensObj)->TryGetNumberField(TEXT("focusDistance"), FocusM))
		{
			FocusDistanceCm = FocusM * 100.0;
		}
		(*LensObj)->TryGetNumberField(TEXT("k1"), K1Val);
		(*LensObj)->TryGetNumberField(TEXT("k2"), K2Val);
	}

	int32 FpsNum = 30000;
	int32 FpsDen = 1001;
	bool bDropFrame = true;
	if (SavedSettings.IsValid())
	{
		FpsNum = SavedSettings->FrameRateNumerator;
		FpsDen = SavedSettings->FrameRateDenominator;
		bDropFrame = SavedSettings->bDropFrame;
	}

	uint64 TaiNs = FAbuClockRuntimeBridge::Get().NowTaiNanoseconds();
	uint32 BcdTimecode = 0;
	FString SmpteString;
	double SubframePhase = 0.0;
	FString LockState = TEXT("OPENTRACKIO_PTP");

	const TSharedPtr<FJsonObject>* TimingObj = nullptr;
	if (RootObj->TryGetObjectField(TEXT("timing"), TimingObj) && TimingObj->IsValid())
	{
		double TaiNsNum = 0.0;
		if ((*TimingObj)->TryGetNumberField(TEXT("taiNs"), TaiNsNum) && TaiNsNum > 0.0)
		{
			TaiNs = static_cast<uint64>(TaiNsNum);
		}
		double BcdNum = 0.0;
		if ((*TimingObj)->TryGetNumberField(TEXT("bcdTimecode"), BcdNum))
		{
			BcdTimecode = static_cast<uint32>(BcdNum);
		}
		(*TimingObj)->TryGetStringField(TEXT("smpteTimecode"), SmpteString);
		(*TimingObj)->TryGetNumberField(TEXT("subframePhase"), SubframePhase);
		(*TimingObj)->TryGetStringField(TEXT("clockLockState"), LockState);

		const TSharedPtr<FJsonObject>* RateObj = nullptr;
		if ((*TimingObj)->TryGetObjectField(TEXT("sampleRate"), RateObj) && RateObj->IsValid())
		{
			(*RateObj)->TryGetNumberField(TEXT("num"), FpsNum);
			(*RateObj)->TryGetNumberField(TEXT("denom"), FpsDen);
			(*RateObj)->TryGetBoolField(TEXT("dropFrame"), bDropFrame);
		}
	}

	if (SmpteString.IsEmpty() || BcdTimecode == 0)
	{
		AbuClockCFrameSnapshot Snap{};
		FAbuClockRuntimeBridge::Get().SynthesizeFromTaiNs(TaiNs, FpsNum, FpsDen, bDropFrame, Snap);
		BcdTimecode = Snap.bcd_timecode;
		SubframePhase = Snap.phase;
		SmpteString = FAbuClockRuntimeBridge::FormatSmpteString(Snap.hours, Snap.minutes, Snap.seconds, Snap.frames, Snap.drop_frame != 0, Snap.phase);
	}

	bool bLeverArm = false, bOrigin = false, bPitchOffset = false;
	RootObj->TryGetBoolField(TEXT("leverArmApplied"), bLeverArm);
	RootObj->TryGetBoolField(TEXT("originApplied"), bOrigin);
	RootObj->TryGetBoolField(TEXT("pitchOffsetApplied"), bPitchOffset);
	const bool bOffsetsApplied = (bLeverArm || bOrigin || bPitchOffset);

	PushSynchronizedCameraFrame(
		XCm, YCm, ZCm,
		PitchDeg, YawDeg, RollDeg,
		FocalLengthMm, FocusDistanceCm,
		K1Val, K2Val,
		TaiNs, BcdTimecode, SmpteString, SubframePhase,
		FpsNum, FpsDen, bDropFrame,
		LockState,
		TEXT("OpenTrackIO (OTrk)"),
		bOffsetsApplied
	);
}

void FLiveLinkAbuTrackSource::ProcessJsonPacket(const FString& PacketData, const FString& ProtocolLabel)
{
	TSharedPtr<FJsonObject> JsonObject;
	TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(PacketData);

	if (!FJsonSerializer::Deserialize(Reader, JsonObject) || !JsonObject.IsValid())
	{
		return;
	}

	const TArray<TSharedPtr<FJsonValue>>* TranslationArray = nullptr;
	const TArray<TSharedPtr<FJsonValue>>* RotationArray = nullptr;
	if (!JsonObject->TryGetArrayField(TEXT("translation"), TranslationArray) ||
		!JsonObject->TryGetArrayField(TEXT("rotation"), RotationArray) ||
		TranslationArray->Num() < 3 || RotationArray->Num() < 3)
	{
		return;
	}

	const double XCm = (*TranslationArray)[0]->AsNumber() * 100.0;
	const double YCm = (*TranslationArray)[1]->AsNumber() * 100.0;
	const double ZCm = (*TranslationArray)[2]->AsNumber() * 100.0;

	const double PitchDeg = (*RotationArray)[0]->AsNumber();
	const double YawDeg = (*RotationArray)[1]->AsNumber();
	const double RollDeg = (*RotationArray)[2]->AsNumber();

	double FocalLength = 24.0;
	JsonObject->TryGetNumberField(TEXT("focalLength"), FocalLength);

	double K1 = 0.0;
	JsonObject->TryGetNumberField(TEXT("k1"), K1);

	double K2 = 0.0;
	JsonObject->TryGetNumberField(TEXT("k2"), K2);

	int32 FpsNum = 30000;
	int32 FpsDen = 1001;
	bool bDropFrame = true;
	if (SavedSettings.IsValid())
	{
		FpsNum = SavedSettings->FrameRateNumerator;
		FpsDen = SavedSettings->FrameRateDenominator;
		bDropFrame = SavedSettings->bDropFrame;
	}

	JsonObject->TryGetNumberField(TEXT("fpsNum"), FpsNum);
	JsonObject->TryGetNumberField(TEXT("fpsDen"), FpsDen);
	JsonObject->TryGetBoolField(TEXT("dropFrame"), bDropFrame);

	uint64 TaiNs = 0;
	double TaiNsDouble = 0.0;
	if (JsonObject->TryGetNumberField(TEXT("taiNs"), TaiNsDouble) && TaiNsDouble > 0.0)
	{
		TaiNs = static_cast<uint64>(TaiNsDouble);
	}
	else
	{
		double UtcSec = 0.0;
		if (JsonObject->TryGetNumberField(TEXT("timestamp"), UtcSec) && UtcSec > 0.0)
		{
			TaiNs = static_cast<uint64>(UtcSec * 1e9) + 37000000000ULL;
		}
		else
		{
			TaiNs = FAbuClockRuntimeBridge::Get().NowTaiNanoseconds();
		}
	}

	uint32 BcdTimecode = 0;
	double BcdDouble = 0.0;
	if (JsonObject->TryGetNumberField(TEXT("bcdTimecode"), BcdDouble))
	{
		BcdTimecode = static_cast<uint32>(BcdDouble);
	}

	FString SmpteString;
	JsonObject->TryGetStringField(TEXT("smpteTimecode"), SmpteString);

	double SubframePhase = 0.0;
	JsonObject->TryGetNumberField(TEXT("subframePhase"), SubframePhase);

	FString LockState = TEXT("LOCKED");
	JsonObject->TryGetStringField(TEXT("clockLockState"), LockState);

	if (SmpteString.IsEmpty() || BcdTimecode == 0)
	{
		AbuClockCFrameSnapshot Snap{};
		FAbuClockRuntimeBridge::Get().SynthesizeFromTaiNs(TaiNs, FpsNum, FpsDen, bDropFrame, Snap);
		BcdTimecode = Snap.bcd_timecode;
		SubframePhase = Snap.phase;
		SmpteString = FAbuClockRuntimeBridge::FormatSmpteString(Snap.hours, Snap.minutes, Snap.seconds, Snap.frames, Snap.drop_frame != 0, Snap.phase);
	}

	bool bLeverArm = false, bOrigin = false, bPitchOffset = false;
	JsonObject->TryGetBoolField(TEXT("leverArmApplied"), bLeverArm);
	JsonObject->TryGetBoolField(TEXT("originApplied"), bOrigin);
	JsonObject->TryGetBoolField(TEXT("pitchOffsetApplied"), bPitchOffset);
	const bool bOffsetsApplied = (bLeverArm || bOrigin || bPitchOffset);

	PushSynchronizedCameraFrame(
		XCm, YCm, ZCm,
		PitchDeg, YawDeg, RollDeg,
		FocalLength, 150.0,
		K1, K2,
		TaiNs, BcdTimecode, SmpteString, SubframePhase,
		FpsNum, FpsDen, bDropFrame,
		LockState,
		ProtocolLabel,
		bOffsetsApplied
	);
}

void FLiveLinkAbuTrackSource::PushSynchronizedCameraFrame(
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
	bool bOffsetsApplied)
{
	if (!LiveLinkClient)
	{
		return;
	}

	const int64 NewPacketCount = ++TotalReceivedPackets;
	const double NowWallSec = FPlatformTime::Seconds();
	LastPacketPlatformSeconds.Store(NowWallSec);

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

	FLiveLinkFrameDataStruct FrameData(FLiveLinkCameraFrameData::StaticStruct());
	FLiveLinkCameraFrameData& CameraFrameData = *FrameData.Cast<FLiveLinkCameraFrameData>();

	CameraFrameData.Transform = FTransform(FRotator(PitchDeg, YawDeg, RollDeg), FVector(XCm, YCm, ZCm));
	CameraFrameData.FocusDistance = static_cast<float>(FocusDistanceCm);

	double FinalFocalLength = FocalLengthMm;
	if (SavedSettings.IsValid())
	{
		ULiveLinkAbuTrackSourceSettings* SettingsToUpdate = SavedSettings.Get();
		const FString BcdHex = FString::Printf(TEXT("0x%08X"), BcdTimecode);
		AsyncTask(ENamedThreads::GameThread, [SettingsToUpdate, FocalLengthMm, K1Val, K2Val, ProtocolLabel, SmpteString, BcdHex, TaiNs, SubframePhase, LockState, NewPacketCount, NowWallSec, bOffsetsApplied]()
		{
			if (SettingsToUpdate && SettingsToUpdate->IsValidLowLevel())
			{
				SettingsToUpdate->LiveFocalLength = static_cast<float>(FocalLengthMm);
				SettingsToUpdate->K1 = static_cast<float>(K1Val);
				SettingsToUpdate->K2 = static_cast<float>(K2Val);
				SettingsToUpdate->ActiveProtocol = ProtocolLabel;
				SettingsToUpdate->LiveSmpteTimecode = SmpteString;
				SettingsToUpdate->LiveBcdTimecodeHex = BcdHex;
				SettingsToUpdate->LiveTaiNanoseconds = static_cast<int64>(TaiNs);
				SettingsToUpdate->LiveSubframePhase = static_cast<float>(SubframePhase);
				SettingsToUpdate->ClockLockState = LockState;
				SettingsToUpdate->ReceivedPacketCount = NewPacketCount;
				SettingsToUpdate->LastPacketWallTimeSec = NowWallSec;
				SettingsToUpdate->bUpstreamOffsetsApplied = bOffsetsApplied;
			}
		});

		if (!SavedSettings->bUseLiveFocalLength)
		{
			FinalFocalLength = SavedSettings->FocalLengthOverride;
		}
	}

	CameraFrameData.FocalLength = static_cast<float>(FinalFocalLength);
	CameraFrameData.WorldTime = FLiveLinkWorldTime(NowWallSec);

	// Construct exact FQualifiedFrameTime for Unreal TimecodeSynchronizer / Composure / Sequencer
	const FTimecode DecodedTc = FAbuClockRuntimeBridge::DecodeBcdTimecode(BcdTimecode, bDropFrame);
	const FFrameRate Rate(FMath::Max(1, FpsNum), FMath::Max(1, FpsDen));
	const FFrameNumber FrameNum = DecodedTc.ToFrameNumber(Rate);
	const FFrameTime FrameTimeWithSubframe(FrameNum, static_cast<float>(FMath::Clamp(SubframePhase, 0.0, 0.999999)));
	CameraFrameData.MetaData.SceneTime = FQualifiedFrameTime(FrameTimeWithSubframe, Rate);

	CameraFrameData.MetaData.StringMetaData.Add(TEXT("SmpteTimecode"), SmpteString);
	CameraFrameData.MetaData.StringMetaData.Add(TEXT("BcdTimecode"), FString::Printf(TEXT("0x%08X"), BcdTimecode));
	CameraFrameData.MetaData.StringMetaData.Add(TEXT("TaiNanoseconds"), FString::Printf(TEXT("%llu"), TaiNs));
	CameraFrameData.MetaData.StringMetaData.Add(TEXT("SubframePhase"), FString::SanitizeFloat(SubframePhase));
	CameraFrameData.MetaData.StringMetaData.Add(TEXT("ClockLockState"), LockState);
	CameraFrameData.MetaData.StringMetaData.Add(TEXT("Protocol"), ProtocolLabel);
	CameraFrameData.MetaData.StringMetaData.Add(TEXT("K1"), FString::SanitizeFloat(K1Val));
	CameraFrameData.MetaData.StringMetaData.Add(TEXT("K2"), FString::SanitizeFloat(K2Val));
	CameraFrameData.MetaData.StringMetaData.Add(TEXT("UpstreamOffsetsApplied"), bOffsetsApplied ? TEXT("true") : TEXT("false"));

	LiveLinkClient->PushSubjectFrameData_AnyThread({ SourceGuid, SubjectName }, MoveTemp(FrameData));
}
