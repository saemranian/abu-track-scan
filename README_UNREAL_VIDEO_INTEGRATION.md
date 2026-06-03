# Unreal Engine Live Video Stream Integration Guide

You can integrate the live video feed from the iOS tracker app into Unreal Engine (UE) using two main approaches:

## Approach 1: Spout GPU Texture Sharing (Recommended - Ultra Low Latency)

Since the Windows desktop app decodes the H.264 RTP stream with high efficiency in real-time, the best way to get the video into UE is to use the Spout sender built into the Windows app. This shares the decoded frame via GPU texture memory directly, resulting in zero latency and zero decoding overhead in Unreal Engine.

### Setup Instructions:
1. **Enable Spout in Desktop App**:
   - Check the **Enable Spout Sharing** checkbox in the Windows app (under "01 // UDP LISTENER OPTIONS").
   - This starts a Spout texture sender named `"AbuTrackVideo"`.
2. **Import Spout Plugin into Unreal Engine**:
   - Download and enable a Spout plugin for Unreal Engine (e.g., **Offworld Live Live-Streaming Toolkit** or the free **Spout-UE** plugin).
3. **Configure Spout Receiver in UE**:
   - Create a **Spout Receiver** actor/component in your level.
   - Set the Sender Name to `"AbuTrackVideo"`.
   - Assign the output texture to a **Render Target**.
4. **Use the Texture**:
   - Create a material from the Render Target and apply it to a plane, screen, or use it as a background/composure element in your scene.

---

## Approach 2: Direct RTP Streaming in UE

If you want to bypass the Windows desktop app and stream H.264 directly from the iPhone to Unreal Engine:

### Setup Instructions:
1. **Use Electra Media Player (UE built-in)**:
   - Enable the **Electra Player** plugin in Unreal Engine (Edit -> Plugins).
2. **Create a Media Player Asset**:
   - In the Content Browser, right-click -> Media -> Media Player (check "Create Media Texture asset").
3. **Play the Stream**:
   - Direct RTP streams need an out-of-band descriptor file (`.sdp`) to tell Electra Player about the H.264 encoding.
   - Create a text file named `stream.sdp` with the following content:
     ```sdp
     v=0
     o=- 0 0 IN IP4 127.0.0.1
     s=No Name
     c=IN IP4 0.0.0.0
     t=0 0
     m=video 8082 RTP/AVP 96
     a=rtpmap:96 H264/90000
     ```
   - In UE, open the Media Player asset and open the `stream.sdp` file path (using `file://...` url) or configure the Media Source pointing to this SDP file.
4. **Create Media Texture**:
   - Apply the Media Texture to a material in your scene.
