# MXMenu design rules

MXMenu should feel like one of macOS's own menu bar extras (Bluetooth, Battery, Sound), not like a web page in a popover. If a choice isn't covered here, copy what Apple's own menus do.

## Menu bar item

- A template SF Symbol (the system tints it for light, dark and Reduce Transparency), at the size of the system's own extras.
- Battery percentage beside it in the system font, like the Battery extra's "Show Percentage".
- No colour in the menu bar.

## Panel

- **Native controls only.** Mini switches (`.toggleStyle(.switch)`, `.controlSize(.mini)`), the standard `Slider`, and pop-up menus. They pick up the user's accent colour, keyboard focus and accessibility for free.
- **System colours only.** Primary and secondary label colours, separators, and the accent colour on controls. No gradients, glows, coloured backgrounds or custom palettes. The one exception is the battery glyph, which goes red when low, as Apple's does.
- **The menu material is the background.** Don't paint over it or nest cards inside it.
- **Typography:** the system font at menu sizes. The header is 13 pt bold, rows are 13 pt regular, and section headings are 11 pt semibold in the secondary colour. No large display numbers.
- **Structure:** a header row (device name, battery), then groups separated by hairline dividers, each with a small heading. It ends with menu-item rows ("Check for Updates…", "Quit") that highlight on hover like real menu items.
- **Spacing:** about 300 pt wide, 14 pt side margins, rows about 22–28 pt tall. Insets line up on one leading edge.
- **Icons:** SF Symbols in 26 pt circles, filled with the accent colour when "on", as in Control Center and the Bluetooth menu. They're used sparingly, only where they help recognition.
- **Words:** title case for control labels, an ellipsis on items that open something else, and no explanatory sentences where a label will do.

## Sources

- [Designing macOS menu bar extras](https://bjango.com/articles/designingmenubarextras/) (Bjango)
- [What I learned building a native macOS menu bar app](https://dev.to/heocoi/what-i-learned-building-a-native-macos-menu-bar-app-4im6)
- [Build a macOS menu bar utility in SwiftUI](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI) (Nil Coalescing)
- Apple's Human Interface Guidelines on menu bar extras, and Apple's own Bluetooth, Battery, Wi-Fi and Sound menus
