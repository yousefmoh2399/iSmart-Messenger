---
name: apple_design
description: "Apple Minimalist Design System: Rules for building clean, modern iOS-style UIs without heavy shadows or borders."
---

# Apple / iOS UI Design Methodology

This skill outlines the exact rules and aesthetic guidelines required to recreate the clean, minimalist, and premium Apple iOS look in Flutter applications, specifically tailored for Arabic/RTL interfaces.

## 1. Typography & Fonts
- **Font Family:** Avoid default Android `Roboto`. Use geometric sans-serif fonts that mimic Apple's `.SF Arabic`. For Google Fonts, **Cairo** or **Tajawal** are excellent choices for Arabic.
- **Font Weights:** Use contrasting weights. `w800/w900` for main headings (Large Titles), `w600` for list tile titles, and `w400/w500` for body text.
- **Colors:** Never use pure black `#000000` for text. Use deep slate/grey like `Color(0xFF0F172A)` for light mode headings, and off-white `Color(0xFFE2E8F0)` for dark mode. Subtitles should use medium contrast (e.g. `onSurfaceVariant`).

## 2. Layout & Surfaces
- **Avoid Heavy Shadows:** Do not use large `blurRadius` drop shadows. Apple uses extremely subtle shadows (e.g., `alpha: 0.02` with blur 4-8) or completely flat surfaces.
- **Translucency over Opacity:** For banners and hero cards, avoid harsh solid primary colors. Instead, use a primary color with `alpha: 0.1` or `0.15` for the background, and solid primary color for the icon/text.
- **Border Radius:** Use continuous curves. Common values are `12`, `14`, `16`, and `24` for large grouping containers.
- **Background Colors:** 
  - Light mode: `Color(0xFFF2F2F7)` for scaffold background, `Colors.white` for cards.
  - Dark mode: `Color(0xFF000000)` for scaffold background, `Color(0xFF1C1C1E)` for cards.

## 3. Inset Grouped Lists (Crucial for Menus/Settings)
Apple heavily relies on "Inset Grouped Lists" for navigation and settings.
- Group related items inside a single `Container` with a `BorderRadius.circular(10` or `12)`.
- **Divider:** Items inside the group must be separated by a hairline divider (`height: 0.5`, `thickness: 0.5`). 
- **Indent:** The divider should be indented to align with the text, skipping the leading icon.
- **Leading:** Icons inside lists should have a small colored rounded square background (e.g., size 30-34, radius 8).
- **Trailing:** Use a subtle `chevron_right_rounded` icon to indicate navigability.

## 4. Horizontal Carousels (Announcements / Featured)
Instead of stacking multiple cards vertically (which clutters the screen), use horizontal carousels:
- Implement using `PageView` with a fixed height or horizontally scrolling `ListView`.
- Include a subtle page indicator (dots) below the carousel.
- Each item should be a clean, slightly padded `Container` with a subtle border.

## 5. Buttons
- Primary buttons should be full width or generously padded, with `BorderRadius.circular(14` or `16)`.
- Avoid gradients on standard buttons. Use solid colors.

## Example: Inset Grouped List Tile
```dart
Container(
  clipBehavior: Clip.antiAlias,
  decoration: BoxDecoration(
    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Column(
    children: [
      _ActionListTile(title: 'Item 1', icon: Icons.folder, showTopDivider: false),
      _ActionListTile(title: 'Item 2', icon: Icons.cloud, showTopDivider: true),
    ],
  ),
)
```
