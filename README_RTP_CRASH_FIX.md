# Post-Mortem: iOS Video Streaming Crash Fix

## Issue Description
During live H.264 video streaming (Level 4 tracking), the iOS application crashed consistently after exactly one frame was submitted.

## Root Cause
The crash was caused by a **runtime integer arithmetic overflow trap** in `LiveVideoStreamingManager.swift` when calculating the RTP timestamp. 

Specifically, the code was:
```swift
let rtpTimestamp = UInt32(ntpTimestamp.truncatingRemainder(dividingBy: 4294967296.0) * 90000.0)
```
- `ntpTimestamp` is the absolute UNIX epoch timestamp (seconds since Jan 1, 1970). At the time of testing, this value is approx. `1,770,000,000.0`.
- Doing `ntpTimestamp.truncatingRemainder(dividingBy: 4,294,967,296.0)` returned approximately `1,770,000,000.0` (since it is smaller than $2^{32}$).
- Multiplying this by the H.264 clock rate of `90,000.0` yielded approximately `159,300,000,000,000.0`.
- Trying to cast `159.3 trillion` into a `UInt32` (which has a maximum limit of `4,294,967,295`) triggered Swift's safety check, resulting in a runtime arithmetic overflow crash.

## Solution
To prevent this, the modulo operation ($2^{32}$) must be applied *after* scaling the timestamp to the 90kHz clock rate, ensuring that the float value is constrained within $[0, 4294967295]$ prior to the cast:
```swift
let rtpTimestamp = UInt32((ntpTimestamp * 90000.0).truncatingRemainder(dividingBy: 4294967296.0))
```

This ensures the cast is always safe, preventing any future integer overflow crashes.
