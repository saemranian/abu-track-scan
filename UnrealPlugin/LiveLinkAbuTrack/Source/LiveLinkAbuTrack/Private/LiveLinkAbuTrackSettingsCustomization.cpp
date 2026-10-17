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

	// 1. Live SMPTE Timecode & Sub-Frame Phase Banner
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
			.Padding(0.0f, 2.0f, 0.0f, 8.0f)
			[
				SNew(SBox)
				.HeightOverride(6.0f)
				[
					SNew(SProgressBar)
					.Percent(this, &FLiveLinkAbuTrackSettingsCustomization::GetSubframePhaseValue)
					.FillColorAndOpacity(FLinearColor(0.0f, 0.90f, 1.0f, 1.0f))
				]
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
					.Text(LOCTEXT("OneClickConfigBtnText", "Configure UE5 TimecodeProvider & Genlock (1-Click)"))
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
						"3. Set Subject Representation to 'AbuTrack' (Camera Role). Focal Length, Aperture, and 6DoF Pose will now stream at 60-120Hz with deterministic SMPTE SceneTime."
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
