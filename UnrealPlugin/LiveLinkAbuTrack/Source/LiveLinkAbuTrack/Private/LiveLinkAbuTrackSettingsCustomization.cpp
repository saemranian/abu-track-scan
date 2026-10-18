#include "LiveLinkAbuTrackSettingsCustomization.h"

#if WITH_EDITOR

#include "LiveLinkAbuTrackSource.h"
#include "DetailLayoutBuilder.h"
#include "DetailCategoryBuilder.h"
#include "DetailWidgetRow.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SExpandableArea.h"
#include "Widgets/Text/STextBlock.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Notifications/SProgressBar.h"
#include "Framework/Notifications/NotificationManager.h"
#include "Widgets/Notifications/SNotificationList.h"
#include "Styling/AppStyle.h"

#define LOCTEXT_NAMESPACE "LiveLinkAbuTrackSettingsCustomization"

TSharedRef<IDetailCustomization> FLiveLinkAbuTrackSettingsCustomization::MakeInstance()
{
	return MakeShareable(new FLiveLinkAbuTrackSettingsCustomization());
}

void FLiveLinkAbuTrackSettingsCustomization::CustomizeDetails(IDetailLayoutBuilder& DetailBuilder)
{
	TArray<TWeakObjectPtr<UObject>> Objects;
	DetailBuilder.GetObjectsBeingCustomized(Objects);
	if (Objects.Num() > 0)
	{
		EditingSettings = Cast<ULiveLinkAbuTrackSourceSettings>(Objects[0].Get());
	}

	IDetailCategoryBuilder& HeaderCategory = DetailBuilder.EditCategory(
		TEXT("00 | Abu Track & Clock Studio HUD"),
		LOCTEXT("AbuTrackHudCategory", "Abu Track & Clock Studio HUD"),
		ECategoryPriority::Important
	);

	// 1. Live SMPTE Timecode, Stream Heartbeat & Sub-Frame Phase Banner
	HeaderCategory.AddCustomRow(LOCTEXT("LiveTimecodeRowFilter", "Abu Clock Live SMPTE Timecode"))
	.WholeRowContent()
	[
		SNew(SBorder)
		.BorderImage(FAppStyle::GetBrush("ToolPanel.DarkGroupBorder"))
		.Padding(FMargin(10.0f, 8.0f))
		[
			SNew(SVerticalBox)

			// Title + Protocol/Lock Status
			+ SVerticalBox::Slot()
			.AutoHeight()
			.Padding(0.0f, 0.0f, 0.0f, 4.0f)
			[
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot()
				.FillWidth(1.0f)
				.VAlign(VAlign_Center)
				[
					SNew(STextBlock)
					.Text(LOCTEXT("HudHeaderLabel", "ABU CLOCK ST 2059-2 MASTER TIMECODE"))
					.Font(IDetailLayoutBuilder::GetDetailFontBold())
					.ColorAndOpacity(FLinearColor(0.0f, 0.90f, 1.0f, 1.0f))
				]
				+ SHorizontalBox::Slot()
				.AutoWidth()
				.VAlign(VAlign_Center)
				[
					SNew(STextBlock)
					.Text(this, &FLiveLinkAbuTrackSettingsCustomization::GetProtocolAndLockText)
					.Font(IDetailLayoutBuilder::GetDetailFont())
					.ColorAndOpacity(FLinearColor(0.0f, 0.90f, 0.46f, 1.0f))
				]
			]

			// Large Monospace Timecode Readout
			+ SVerticalBox::Slot()
			.AutoHeight()
			.Padding(0.0f, 2.0f, 0.0f, 4.0f)
			[
				SNew(STextBlock)
				.Text(this, &FLiveLinkAbuTrackSettingsCustomization::GetLiveTimecodeText)
				.Font(FCoreStyle::GetDefaultFontStyle("Mono", 16))
				.ColorAndOpacity(FLinearColor::White)
			]

			// Sub-Frame Phase Progress Bar
			+ SVerticalBox::Slot()
			.AutoHeight()
			.Padding(0.0f, 2.0f, 0.0f, 6.0f)
			[
				SNew(SBox)
				.HeightOverride(6.0f)
				[
					SNew(SProgressBar)
					.Percent(this, &FLiveLinkAbuTrackSettingsCustomization::GetSubframePhaseValue)
					.FillColorAndOpacity(FLinearColor(0.0f, 0.90f, 1.0f, 1.0f))
				]
			]

			// Live UDP Stream Heartbeat / Stale Status & Packet Counter
			+ SVerticalBox::Slot()
			.AutoHeight()
			.Padding(0.0f, 0.0f, 0.0f, 8.0f)
			[
				SNew(STextBlock)
				.Text(this, &FLiveLinkAbuTrackSettingsCustomization::GetStreamHealthText)
				.Font(IDetailLayoutBuilder::GetDetailFontBold())
				.ColorAndOpacity(this, &FLiveLinkAbuTrackSettingsCustomization::GetStreamHealthColor)
			]

			// 1-Click Configure Engine TimecodeProvider & CustomTimeStep Button
			+ SVerticalBox::Slot()
			.AutoHeight()
			.Padding(0.0f, 2.0f, 0.0f, 6.0f)
			[
				SNew(SButton)
				.HAlign(HAlign_Center)
				.ContentPadding(FMargin(8.0f, 5.0f))
				.ToolTipText(LOCTEXT(
					"OneClickConfigTooltip",
					"Automatically assigns UAbuClockTimecodeProvider and UAbuClockCustomTimeStep to Unreal Engine with matching FPS and Drop-Frame settings."
				))
				.OnClicked(this, &FLiveLinkAbuTrackSettingsCustomization::OnConfigureEngineTimecodeClicked)
				[
					SNew(STextBlock)
					.Text(this, &FLiveLinkAbuTrackSettingsCustomization::GetOneClickButtonText)
					.Font(IDetailLayoutBuilder::GetDetailFontBold())
				]
			]

			// Collapsible Quick Start Virtual Production Setup Guide
			+ SVerticalBox::Slot()
			.AutoHeight()
			.Padding(0.0f, 4.0f, 0.0f, 0.0f)
			[
				SNew(SExpandableArea)
				.AreaTitle(LOCTEXT("QuickGuideAreaTitle", "Quick Start Virtual Production & AR Setup Guide"))
				.InitiallyCollapsed(true)
				.Padding(FMargin(8.0f, 6.0f))
				.BodyContent()
				[
					SNew(STextBlock)
					.AutoWrapText(true)
					.Font(IDetailLayoutBuilder::GetDetailFont())
					.Text(LOCTEXT(
						"QuickGuideBodyText",
						"1. Click 'Configure UE5 TimecodeProvider & Genlock (1-Click)' above to lock UE5's global Timecode & Render Loop to Abu Clock.\n"
						"2. Select your CineCameraActor in the Level Outliner -> Add Component -> 'LiveLinkComponentController'.\n"
						"3. Set Subject Representation to 'AbuTrack' (Camera Role). Focal Length, Aperture, and 6DoF Pose will now stream at 60-120Hz with deterministic SMPTE SceneTime.\n"
						"4. Port Topology: Use UDP 8080 when streaming directly from iOS, or UDP 8081 when receiving forwarded packets from the Windows Desktop Workstation."
					))
				]
			]
		]
	];
}

FReply FLiveLinkAbuTrackSettingsCustomization::OnConfigureEngineTimecodeClicked()
{
	if (EditingSettings.IsValid())
	{
		EditingSettings->ConfigureEngineTimecodeAndGenlock();

		const FText NotificationText = FText::FromString(FString::Printf(
			TEXT("Abu Clock TimecodeProvider & Genlock CustomTimeStep bound to GEngine (%d/%d fps, %s)"),
			EditingSettings->FrameRateNumerator,
			EditingSettings->FrameRateDenominator,
			EditingSettings->bDropFrame ? TEXT("Drop-Frame") : TEXT("Non-Drop-Frame")
		));

		FNotificationInfo Info(NotificationText);
		Info.bFireAndForget = true;
		Info.FadeInDuration = 0.15f;
		Info.FadeOutDuration = 0.5f;
		Info.ExpireDuration = 4.0f;
		Info.bUseThrobber = false;
		Info.bUseSuccessFailIcons = true;

		TSharedPtr<SNotificationItem> NotificationItem = FSlateNotificationManager::Get().AddNotification(Info);
		if (NotificationItem.IsValid())
		{
			NotificationItem->SetCompletionState(SNotificationItem::CS_Success);
		}
	}
	return FReply::Handled();
}

FText FLiveLinkAbuTrackSettingsCustomization::GetLiveTimecodeText() const
{
	if (EditingSettings.IsValid())
	{
		return FText::FromString(FString::Printf(
			TEXT("%s   (%s)"),
			*EditingSettings->LiveSmpteTimecode,
			*EditingSettings->LiveBcdTimecodeHex
		));
	}
	return LOCTEXT("DefaultTcText", "00:00:00;00.00   (0x00000000)");
}

FText FLiveLinkAbuTrackSettingsCustomization::GetProtocolAndLockText() const
{
	if (EditingSettings.IsValid())
	{
		return FText::FromString(FString::Printf(
			TEXT("[%s] • %s"),
			*EditingSettings->ClockLockState,
			*EditingSettings->ActiveProtocol
		));
	}
	return LOCTEXT("DefaultLockText", "[WAITING]");
}

FText FLiveLinkAbuTrackSettingsCustomization::GetStreamHealthText() const
{
	if (!EditingSettings.IsValid())
	{
		return LOCTEXT("StreamHealthInvalid", "● STREAM OFFLINE");
	}
	if (EditingSettings->ReceivedPacketCount <= 0)
	{
		return FText::FromString(FString::Printf(
			TEXT("● WAITING FOR UDP STREAM ON PORT %d..."),
			EditingSettings->Port
		));
	}
	const double ElapsedSec = FPlatformTime::Seconds() - EditingSettings->LastPacketWallTimeSec;
	const FString OffsetTag = EditingSettings->bUpstreamOffsetsApplied
		? TEXT(" | Upstream Offsets: APPLIED")
		: TEXT("");
	if (ElapsedSec <= 2.0)
	{
		return FText::FromString(FString::Printf(
			TEXT("● STREAM ONLINE • %lld pkts (UDP %d%s)"),
			EditingSettings->ReceivedPacketCount,
			EditingSettings->Port,
			*OffsetTag
		));
	}
	return FText::FromString(FString::Printf(
		TEXT("● STREAM STALE / OFFLINE • Last packet %.1fs ago (%lld pkts)"),
		ElapsedSec,
		EditingSettings->ReceivedPacketCount
	));
}

FSlateColor FLiveLinkAbuTrackSettingsCustomization::GetStreamHealthColor() const
{
	if (!EditingSettings.IsValid() || EditingSettings->ReceivedPacketCount <= 0)
	{
		return FSlateColor(FLinearColor(1.0f, 0.72f, 0.15f, 1.0f)); // Amber waiting
	}
	const double ElapsedSec = FPlatformTime::Seconds() - EditingSettings->LastPacketWallTimeSec;
	if (ElapsedSec <= 2.0)
	{
		return FSlateColor(FLinearColor(0.18f, 0.90f, 0.48f, 1.0f)); // Green online
	}
	return FSlateColor(FLinearColor(1.0f, 0.28f, 0.34f, 1.0f)); // Red stale
}

FText FLiveLinkAbuTrackSettingsCustomization::GetOneClickButtonText() const
{
	if (EditingSettings.IsValid() && EditingSettings->bEngineGenlockConfigured)
	{
		return LOCTEXT("OneClickConfigActiveBtnText", "✔ UE5 TimecodeProvider & Genlock Active (Click to Re-Sync)");
	}
	return LOCTEXT("OneClickConfigBtnText", "Configure UE5 TimecodeProvider & Genlock (1-Click)");
}

TOptional<float> FLiveLinkAbuTrackSettingsCustomization::GetSubframePhaseValue() const
{
	if (EditingSettings.IsValid())
	{
		return FMath::Clamp(EditingSettings->LiveSubframePhase, 0.0f, 1.0f);
	}
	return 0.0f;
}

#undef LOCTEXT_NAMESPACE

#endif // WITH_EDITOR
