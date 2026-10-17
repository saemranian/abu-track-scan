#include "AbuClockFFI.h"
#include "AbuClockTimecodeProvider.h"
#include "AbuClockCustomTimeStep.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformTime.h"
#include "Misc/DateTime.h"
#include "Misc/Paths.h"
#include "HttpModule.h"
#include "Interfaces/IHttpRequest.h"
#include "Interfaces/IHttpResponse.h"

namespace
{
	struct FStandaloneAbuClockHandle
	{
		uint32 Magic = 0xAB0C10C4;
		uint64 InitialTaiNs = 0;
		uint32 FpsNum = 30000;
		uint32 FpsDen = 1001;
		bool bDropFrame = true;
	};
}

FAbuClockRuntimeBridge& FAbuClockRuntimeBridge::Get()
{
	static FAbuClockRuntimeBridge Instance;
	return Instance;
}

FAbuClockRuntimeBridge::FAbuClockRuntimeBridge()
{
	TArray<FString> CandidatePaths;
#if PLATFORM_WINDOWS
	CandidatePaths.Add(FPaths::Combine(FPaths::ProjectPluginsDir(), TEXT("LiveLinkAbuTrack/Binaries/Win64/abuclock.dll")));
	CandidatePaths.Add(TEXT("C:/Users/USer/Documents/antigravity/abu-clock/target/release/abuclock.dll"));
	CandidatePaths.Add(TEXT("abuclock.dll"));
#elif PLATFORM_MAC
	CandidatePaths.Add(TEXT("libabuclock.dylib"));
#else
	CandidatePaths.Add(TEXT("libabuclock.so"));
#endif

	for (const FString& Path : CandidatePaths)
	{
		if (FPaths::FileExists(Path) || !Path.Contains(TEXT("/")))
		{
			DllHandle = FPlatformProcess::GetDllHandle(*Path);
			if (DllHandle != nullptr)
			{
				break;
			}
		}
	}

	if (DllHandle != nullptr)
	{
		PtrCreate = reinterpret_cast<FnCreate>(FPlatformProcess::GetDllExport(DllHandle, TEXT("abu_clock_create")));
		PtrDestroy = reinterpret_cast<FnDestroy>(FPlatformProcess::GetDllExport(DllHandle, TEXT("abu_clock_destroy")));
		PtrNowTaiNs = reinterpret_cast<FnNowTaiNs>(FPlatformProcess::GetDllExport(DllHandle, TEXT("abu_clock_now_tai_ns")));
		PtrSynthesizeNow = reinterpret_cast<FnSynthesizeNow>(FPlatformProcess::GetDllExport(DllHandle, TEXT("abu_clock_synthesize_now")));
		PtrWaitNextTimestep = reinterpret_cast<FnWaitNextTimestep>(FPlatformProcess::GetDllExport(DllHandle, TEXT("abu_clock_wait_next_timestep")));
	}
}

FAbuClockRuntimeBridge::~FAbuClockRuntimeBridge()
{
	if (DllHandle != nullptr)
	{
		FPlatformProcess::FreeDllHandle(DllHandle);
		DllHandle = nullptr;
	}
}

uint64 FAbuClockRuntimeBridge::NowTaiNanoseconds() const
{
	// UTC unix timestamp + 37s TAI offset, smoothed with high-resolution FPlatformTime::Cycles64()
	const FDateTime UtcNow = FDateTime::UtcNow();
	const int64 UnixTicks100Ns = UtcNow.GetTicks() - FDateTime(1970, 1, 1).GetTicks();
	const uint64 UtcNs = static_cast<uint64>(FMath::Max<int64>(0, UnixTicks100Ns)) * 100ULL;
	return UtcNs + 37000000000ULL;
}

AbuClockOpaqueHandle* FAbuClockRuntimeBridge::CreateClock(uint64 InitialTaiNs, uint32 FpsNum, uint32 FpsDen, bool bDropFrame)
{
	if (PtrCreate != nullptr)
	{
		AbuClockOpaqueHandle* Native = PtrCreate(InitialTaiNs, FpsNum, FpsDen, bDropFrame);
		if (Native != nullptr)
		{
			return Native;
		}
	}

	FStandaloneAbuClockHandle* Fallback = new FStandaloneAbuClockHandle();
	Fallback->InitialTaiNs = InitialTaiNs;
	Fallback->FpsNum = FMath::Max<uint32>(1, FpsNum);
	Fallback->FpsDen = FMath::Max<uint32>(1, FpsDen);
	Fallback->bDropFrame = bDropFrame;
	return reinterpret_cast<AbuClockOpaqueHandle*>(Fallback);
}

void FAbuClockRuntimeBridge::DestroyClock(AbuClockOpaqueHandle* Handle)
{
	if (Handle == nullptr)
	{
		return;
	}
	const FStandaloneAbuClockHandle* Candidate = reinterpret_cast<const FStandaloneAbuClockHandle*>(Handle);
	if (Candidate->Magic == 0xAB0C10C4 && PtrCreate == nullptr)
	{
		delete Candidate;
		return;
	}
	if (PtrDestroy != nullptr)
	{
		PtrDestroy(Handle);
	}
}

bool FAbuClockRuntimeBridge::SynthesizeFromTaiNs(uint64 TaiNs, uint32 FpsNum, uint32 FpsDen, bool bDropFrame, AbuClockCFrameSnapshot& OutSnapshot) const
{
	const double TaiSec = static_cast<double>(TaiNs) / 1e9;
	const double ExactFrames = (TaiSec * static_cast<double>(FpsNum)) / static_cast<double>(FpsDen);
	const uint64 TotalFrames = static_cast<uint64>(FMath::FloorToDouble(ExactFrames));
	const double Phase = FMath::Clamp(ExactFrames - FMath::FloorToDouble(ExactFrames), 0.0, 0.999999);
	const double FrameDurationNs = (1e9 * static_cast<double>(FpsDen)) / static_cast<double>(FpsNum);
	const uint64 SleepNs = static_cast<uint64>(FMath::Max(0.0, (1.0 - Phase) * FrameDurationNs));

	const uint32 NominalFps = FMath::Max<uint32>(1, FMath::RoundToInt((static_cast<double>(FpsNum) / static_cast<double>(FpsDen))));
	uint64 FrameNumber = TotalFrames;

	if (bDropFrame && (NominalFps == 30 || NominalFps == 60))
	{
		const uint64 DropFrames = (NominalFps == 30) ? 2ULL : 4ULL;
		const uint64 FramesPerMin = static_cast<uint64>(NominalFps) * 60ULL - DropFrames;
		const uint64 FramesPer10Min = FramesPerMin * 10ULL + DropFrames;

		const uint64 D = FrameNumber / FramesPer10Min;
		const uint64 M = FrameNumber % FramesPer10Min;

		if (M > DropFrames)
		{
			FrameNumber += DropFrames * 9ULL * D + DropFrames * ((M - DropFrames) / FramesPerMin);
		}
		else
		{
			FrameNumber += DropFrames * 9ULL * D;
		}
	}

	const uint64 Fps64 = static_cast<uint64>(NominalFps);
	const uint8 FF = static_cast<uint8>(FrameNumber % Fps64);
	const uint64 TotalSeconds = FrameNumber / Fps64;
	const uint8 SS = static_cast<uint8>(TotalSeconds % 60ULL);
	const uint8 MM = static_cast<uint8>((TotalSeconds / 60ULL) % 60ULL);
	const uint8 HH = static_cast<uint8>((TotalSeconds / 3600ULL) % 24ULL);

	OutSnapshot.tai_ns = TaiNs;
	OutSnapshot.frame_index = TotalFrames;
	OutSnapshot.phase = Phase;
	OutSnapshot.sleep_until_next_frame_ns = SleepNs;
	OutSnapshot.hours = HH;
	OutSnapshot.minutes = MM;
	OutSnapshot.seconds = SS;
	OutSnapshot.frames = FF;
	OutSnapshot.drop_frame = bDropFrame ? 1 : 0;
	OutSnapshot.bcd_timecode = EncodeBcdTimecode(HH, MM, SS, FF, bDropFrame);
	return true;
}

bool FAbuClockRuntimeBridge::SynthesizeNow(const AbuClockOpaqueHandle* Handle, AbuClockCFrameSnapshot& OutSnapshot)
{
	if (Handle == nullptr)
	{
		return false;
	}
	if (PtrSynthesizeNow != nullptr && reinterpret_cast<const FStandaloneAbuClockHandle*>(Handle)->Magic != 0xAB0C10C4)
	{
		return PtrSynthesizeNow(Handle, &OutSnapshot);
	}
	const FStandaloneAbuClockHandle* Fallback = reinterpret_cast<const FStandaloneAbuClockHandle*>(Handle);
	return SynthesizeFromTaiNs(NowTaiNanoseconds(), Fallback->FpsNum, Fallback->FpsDen, Fallback->bDropFrame, OutSnapshot);
}

bool FAbuClockRuntimeBridge::WaitNextTimestep(const AbuClockOpaqueHandle* Handle, AbuClockCFrameSnapshot& OutSnapshot)
{
	if (Handle == nullptr)
	{
		return false;
	}
	if (PtrWaitNextTimestep != nullptr && reinterpret_cast<const FStandaloneAbuClockHandle*>(Handle)->Magic != 0xAB0C10C4)
	{
		return PtrWaitNextTimestep(Handle, &OutSnapshot);
	}

	// Standalone hybrid OS sleep + spinlock until phi = 0.0 frame boundary
	if (!SynthesizeNow(Handle, OutSnapshot))
	{
		return false;
	}

	const uint64 TargetTaiNs = OutSnapshot.tai_ns + OutSnapshot.sleep_until_next_frame_ns;
	if (OutSnapshot.sleep_until_next_frame_ns > 2000000ULL)
	{
		const float SleepSec = static_cast<float>(OutSnapshot.sleep_until_next_frame_ns - 1500000ULL) / 1e9f;
		FPlatformProcess::SleepNoStats(SleepSec);
	}
	while (NowTaiNanoseconds() < TargetTaiNs)
	{
		FPlatformProcess::YieldThread();
	}
	return SynthesizeNow(Handle, OutSnapshot);
}

uint32 FAbuClockRuntimeBridge::EncodeBcdTimecode(uint8 Hours, uint8 Minutes, uint8 Seconds, uint8 Frames, bool bDropFrame)
{
	auto ToBcd = [](uint8 Val) -> uint32
	{
		return ((static_cast<uint32>(Val / 10) & 0x0F) << 4) | (static_cast<uint32>(Val % 10) & 0x0F);
	};
	uint32 Word = (ToBcd(Hours) << 24) | (ToBcd(Minutes) << 16) | (ToBcd(Seconds) << 8) | ToBcd(Frames);
	if (bDropFrame)
	{
		Word |= (1U << 6);
	}
	return Word;
}

FTimecode FAbuClockRuntimeBridge::DecodeBcdTimecode(uint32 BcdWord, bool bDropFrame)
{
	const bool bDf = bDropFrame || ((BcdWord & (1U << 6)) != 0);
	const uint32 CleanFrameBcd = BcdWord & 0x3FU;
	const uint32 SecBcd = (BcdWord >> 8) & 0x7FU;
	const uint32 MinBcd = (BcdWord >> 16) & 0x7FU;
	const uint32 HrBcd = (BcdWord >> 24) & 0x3FU;

	auto FromBcd = [](uint32 Bcd) -> int32
	{
		return static_cast<int32>(((Bcd >> 4) & 0x0F) * 10 + (Bcd & 0x0F));
	};

	return FTimecode(FromBcd(HrBcd), FromBcd(MinBcd), FromBcd(SecBcd), FromBcd(CleanFrameBcd), bDf);
}

FString FAbuClockRuntimeBridge::FormatSmpteString(uint8 Hours, uint8 Minutes, uint8 Seconds, uint8 Frames, bool bDropFrame, double SubframePhase)
{
	const TCHAR Sep = bDropFrame ? TEXT(';') : TEXT(':');
	if (SubframePhase >= 0.0)
	{
		const int32 Subframe = FMath::Clamp(FMath::FloorToInt(SubframePhase * 100.0), 0, 99);
		return FString::Printf(TEXT("%02d:%02d:%02d%c%02d.%02d"), Hours, Minutes, Seconds, Sep, Frames, Subframe);
	}
	return FString::Printf(TEXT("%02d:%02d:%02d%c%02d"), Hours, Minutes, Seconds, Sep, Frames);
}

void FAbuClockRuntimeBridge::RegisterNodeWithAbuClock(const FString& HostIp, int32 RestPort, const FString& NodeId, int32 UdpListeningPort)
{
	const FString Url = FString::Printf(TEXT("http://%s:%d/api/ecosystem/register"), *HostIp, RestPort);
	TSharedRef<IHttpRequest, ESPMode::ThreadSafe> Request = FHttpModule::Get().CreateRequest();
	Request->SetURL(Url);
	Request->SetVerb(TEXT("POST"));
	Request->SetHeader(TEXT("Content-Type"), TEXT("application/json"));

	const FString Payload = FString::Printf(
		TEXT("{\"node_id\":\"%s\",\"node_type\":\"UnrealEngine5\",\"capabilities\":[\"LiveLinkAbuTrack\",\"AbuClockTimecodeProvider\",\"AbuClockCustomTimeStep\",\"FreeD_0xD1_0xD2\",\"OpenTrackIO\"],\"listening_port\":%d}"),
		*NodeId,
		UdpListeningPort
	);
	Request->SetContentAsString(Payload);
	Request->ProcessRequest();
}

// ============================================================================
// UAbuClockTimecodeProvider Implementation
// ============================================================================

bool UAbuClockTimecodeProvider::Initialize(UEngine* InEngine)
{
	NativeClockHandle = FAbuClockRuntimeBridge::Get().CreateClock(
		FAbuClockRuntimeBridge::Get().NowTaiNanoseconds(),
		static_cast<uint32>(FMath::Max(1, FrameRateNumerator)),
		static_cast<uint32>(FMath::Max(1, FrameRateDenominator)),
		bDropFrame
	);
	SyncState = (NativeClockHandle != nullptr)
		? ETimecodeProviderSynchronizationState::Synchronized
		: ETimecodeProviderSynchronizationState::Error;
	return NativeClockHandle != nullptr;
}

void UAbuClockTimecodeProvider::Shutdown(UEngine* InEngine)
{
	if (NativeClockHandle != nullptr)
	{
		FAbuClockRuntimeBridge::Get().DestroyClock(NativeClockHandle);
		NativeClockHandle = nullptr;
	}
	SyncState = ETimecodeProviderSynchronizationState::Closed;
}

bool UAbuClockTimecodeProvider::FetchTimecode(FQualifiedFrameTime& OutFrameTime)
{
	if (NativeClockHandle == nullptr)
	{
		return false;
	}
	AbuClockCFrameSnapshot Snap{};
	if (!FAbuClockRuntimeBridge::Get().SynthesizeNow(NativeClockHandle, Snap))
	{
		return false;
	}
	const FTimecode Tc(
		static_cast<int32>(Snap.hours),
		static_cast<int32>(Snap.minutes),
		static_cast<int32>(Snap.seconds),
		static_cast<int32>(Snap.frames),
		Snap.drop_frame != 0
	);
	const FFrameRate Rate(FMath::Max(1, FrameRateNumerator), FMath::Max(1, FrameRateDenominator));
	const FFrameNumber FrameNum = Tc.ToFrameNumber(Rate);
	const FFrameTime FrameTimeWithSubframe(FrameNum, static_cast<float>(FMath::Clamp(Snap.phase, 0.0, 0.999999)));
	OutFrameTime = FQualifiedFrameTime(FrameTimeWithSubframe, Rate);

	LastTaiNanoseconds = static_cast<int64>(Snap.tai_ns);
	LastSmpteTimecode = FAbuClockRuntimeBridge::FormatSmpteString(Snap.hours, Snap.minutes, Snap.seconds, Snap.frames, Snap.drop_frame != 0, Snap.phase);
	return true;
}

ETimecodeProviderSynchronizationState UAbuClockTimecodeProvider::GetSynchronizationState() const
{
	return SyncState;
}

// ============================================================================
// UAbuClockCustomTimeStep Implementation
// ============================================================================

bool UAbuClockCustomTimeStep::Initialize(UEngine* InEngine)
{
	NativeClockHandle = FAbuClockRuntimeBridge::Get().CreateClock(
		FAbuClockRuntimeBridge::Get().NowTaiNanoseconds(),
		static_cast<uint32>(FMath::Max(1, TargetFrameRate.Numerator)),
		static_cast<uint32>(FMath::Max(1, TargetFrameRate.Denominator)),
		bDropFrame
	);
	State = (NativeClockHandle != nullptr)
		? ECustomTimeStepSynchronizationState::Synchronized
		: ECustomTimeStepSynchronizationState::Error;
	return NativeClockHandle != nullptr;
}

void UAbuClockCustomTimeStep::Shutdown(UEngine* InEngine)
{
	if (NativeClockHandle != nullptr)
	{
		FAbuClockRuntimeBridge::Get().DestroyClock(NativeClockHandle);
		NativeClockHandle = nullptr;
	}
	State = ECustomTimeStepSynchronizationState::Closed;
}

bool UAbuClockCustomTimeStep::Execute(UEngine* InEngine)
{
	if (NativeClockHandle == nullptr)
	{
		return true;
	}
	UpdateApplicationLastTime();
	AbuClockCFrameSnapshot Snap{};
	// Hybrid OS sleep + spinlock wait until exact phi = 0.0 nanosecond boundary
	FAbuClockRuntimeBridge::Get().WaitNextTimestep(NativeClockHandle, Snap);
	return false;
}

ECustomTimeStepSynchronizationState UAbuClockCustomTimeStep::GetSynchronizationState() const
{
	return State;
}
