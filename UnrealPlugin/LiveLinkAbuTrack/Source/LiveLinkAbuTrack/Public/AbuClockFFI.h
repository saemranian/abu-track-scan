#pragma once

#include "CoreMinimal.h"
#include "Misc/Timecode.h"
#include "Misc/FrameRate.h"
#include "Misc/QualifiedFrameTime.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AbuClockOpaqueHandle AbuClockOpaqueHandle;

typedef struct AbuClockCFrameSnapshot
{
	uint64 tai_ns;
	uint64 frame_index;
	double phase;
	uint64 sleep_until_next_frame_ns;
	uint32 bcd_timecode;
	uint8 hours;
	uint8 minutes;
	uint8 seconds;
	uint8 frames;
	uint8 drop_frame;
} AbuClockCFrameSnapshot;

typedef struct AbuClockCPose6DoF
{
	uint8 camera_id;
	double pan_deg;
	double tilt_deg;
	double roll_deg;
	double x_mm;
	double y_mm;
	double z_mm;
	uint32 zoom_raw;
	uint32 focus_raw;
} AbuClockCPose6DoF;

#ifdef __cplusplus
}
#endif

/**
 * FAbuClockRuntimeBridge
 *
 * Dynamically binds to libabuclock (`abuclock.dll` / `libabuclock.dylib` / `libabuclock.so`)
 * if present in the system or plugin binaries, and provides a deterministic C++ SMPTE ST 2059-2 /
 * ST 12-1 fallback synthesis & hybrid sleep+spinlock engine when running standalone in UE5.
 */
class LIVELINKABUTRACK_API FAbuClockRuntimeBridge
{
public:
	static FAbuClockRuntimeBridge& Get();

	AbuClockOpaqueHandle* CreateClock(uint64 InitialTaiNs, uint32 FpsNum, uint32 FpsDen, bool bDropFrame);
	void DestroyClock(AbuClockOpaqueHandle* Handle);

	bool SynthesizeNow(const AbuClockOpaqueHandle* Handle, AbuClockCFrameSnapshot& OutSnapshot);
	bool SynthesizeFromTaiNs(uint64 TaiNs, uint32 FpsNum, uint32 FpsDen, bool bDropFrame, AbuClockCFrameSnapshot& OutSnapshot) const;
	bool WaitNextTimestep(const AbuClockOpaqueHandle* Handle, AbuClockCFrameSnapshot& OutSnapshot);

	uint64 NowTaiNanoseconds() const;
	static FTimecode DecodeBcdTimecode(uint32 BcdWord, bool bDropFrame);
	static uint32 EncodeBcdTimecode(uint8 Hours, uint8 Minutes, uint8 Seconds, uint8 Frames, bool bDropFrame);
	static FString FormatSmpteString(uint8 Hours, uint8 Minutes, uint8 Seconds, uint8 Frames, bool bDropFrame, double SubframePhase = -1.0);

	void RegisterNodeWithAbuClock(const FString& HostIp, int32 RestPort, const FString& NodeId, int32 UdpListeningPort);

private:
	FAbuClockRuntimeBridge();
	~FAbuClockRuntimeBridge();

	void* DllHandle = nullptr;

	typedef AbuClockOpaqueHandle* (*FnCreate)(uint64, uint32, uint32, bool);
	typedef void (*FnDestroy)(AbuClockOpaqueHandle*);
	typedef uint64 (*FnNowTaiNs)(const AbuClockOpaqueHandle*);
	typedef bool (*FnSynthesizeNow)(const AbuClockOpaqueHandle*, AbuClockCFrameSnapshot*);
	typedef bool (*FnWaitNextTimestep)(const AbuClockOpaqueHandle*, AbuClockCFrameSnapshot*);

	FnCreate PtrCreate = nullptr;
	FnDestroy PtrDestroy = nullptr;
	FnNowTaiNs PtrNowTaiNs = nullptr;
	FnSynthesizeNow PtrSynthesizeNow = nullptr;
	FnWaitNextTimestep PtrWaitNextTimestep = nullptr;
};
