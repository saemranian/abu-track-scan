import os
import json
from PIL import Image, ImageDraw, ImageFont

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def render_abu_green_a_icon(size: int = 1024, rounded_corners: bool = True) -> Image.Image:
    """
    Renders the unified 'A' on green background app icon (supersampled 2x for crisp anti-aliasing).
    Matches the clean geometric 'A' on green rounded square design.
    """
    ss = size * 2
    img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Vibrant emerald/mint green background matching the reference icon in green
    bg_green = (52, 211, 153, 255)  # #34D399 / vibrant studio green
    fg_dark = (17, 24, 39, 255)     # #111827 deep charcoal 'A'

    if rounded_corners:
        margin = int(ss * 0.04)
        radius = int(ss * 0.22)
        draw.rounded_rectangle(
            [margin, margin, ss - margin, ss - margin],
            radius=radius,
            fill=bg_green,
        )
    else:
        # iOS App Store 1024x1024 icon requires full bleed (iOS applies the squircle mask)
        draw.rectangle([0, 0, ss, ss], fill=bg_green)

    # Draw a crisp, geometric bold 'A' using polygon/vector coordinates so it never depends on missing system fonts
    # Total height of 'A': from y = 0.23 * ss to y = 0.77 * ss
    cx = ss / 2.0
    top_y = ss * 0.22
    bot_y = ss * 0.78
    half_top_w = ss * 0.058
    half_bot_w = ss * 0.235
    stroke_w = ss * 0.095

    # Outer trapezoid of 'A'
    outer_pts = [
        (cx - half_top_w, top_y),
        (cx + half_top_w, top_y),
        (cx + half_bot_w, bot_y),
        (cx + half_bot_w - stroke_w, bot_y),
        (cx, top_y + stroke_w * 1.15),
        (cx - half_bot_w + stroke_w, bot_y),
        (cx - half_bot_w, bot_y),
    ]
    draw.polygon(outer_pts, fill=fg_dark)

    # Crossbar of 'A'
    bar_top = ss * 0.545
    bar_bot = ss * 0.625
    bar_half_w = ss * 0.135
    draw.rectangle(
        [cx - bar_half_w, bar_top, cx + bar_half_w, bar_bot],
        fill=fg_dark,
    )

    resampling = getattr(Image, "Resampling", Image).LANCZOS
    return img.resize((size, size), resampling)


def main():
    # 1. Desktop App Assets (Windows .ico and .png)
    desktop_assets_dir = os.path.join(ROOT_DIR, "DesktopSync", "assets")
    os.makedirs(desktop_assets_dir, exist_ok=True)

    icon_master = render_abu_green_a_icon(512, rounded_corners=True)
    png_256 = icon_master.resize((256, 256), getattr(Image, "Resampling", Image).LANCZOS)
    png_path = os.path.join(desktop_assets_dir, "abu_icon.png")
    png_256.save(png_path, format="PNG")

    ico_path = os.path.join(desktop_assets_dir, "abu_icon.ico")
    icon_master.save(
        ico_path,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(f"Saved Desktop icons:\n  {png_path}\n  {ico_path}")

    # 2. Unreal Engine 5 Plugin Resources (Icon128.png)
    ue_res_dir = os.path.join(ROOT_DIR, "UnrealPlugin", "LiveLinkAbuTrack", "Resources")
    os.makedirs(ue_res_dir, exist_ok=True)
    ue_icon_128 = icon_master.resize((128, 128), getattr(Image, "Resampling", Image).LANCZOS)
    ue_icon_path = os.path.join(ue_res_dir, "Icon128.png")
    ue_icon_128.save(ue_icon_path, format="PNG")
    print(f"Saved UE5 Plugin icon:\n  {ue_icon_path}")

    # 3. iOS App Asset Catalog (Sources/Assets.xcassets/AppIcon.appiconset)
    ios_appicon_dir = os.path.join(ROOT_DIR, "Sources", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(ios_appicon_dir, exist_ok=True)
    ios_icon_1024 = render_abu_green_a_icon(1024, rounded_corners=False).convert("RGB")
    ios_icon_path = os.path.join(ios_appicon_dir, "AppIcon.png")
    ios_icon_1024.save(ios_icon_path, format="PNG")

    contents_json = {
        "images": [
            {
                "filename": "AppIcon.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024"
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1
        }
    }
    with open(os.path.join(ios_appicon_dir, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents_json, f, indent=2)

    assets_root_contents = {
        "info": {
            "author": "xcode",
            "version": 1
        }
    }
    with open(os.path.join(ROOT_DIR, "Sources", "Assets.xcassets", "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(assets_root_contents, f, indent=2)

    print(f"Saved iOS AppIcon asset catalog:\n  {ios_icon_path}")


if __name__ == "__main__":
    main()
