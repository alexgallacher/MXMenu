# MXMenu design rules

MXMenu uses a calm, light "web app" look that Alex picked: one white card on an off-white page, a single blue accent, soft tinted tags, and thin-bordered rows. Every colour has a matching dark-mode value in `Theme.swift`. If a choice isn't covered here, keep it quiet: fewer colours, more whitespace.

## Menu bar item

- A template SF Symbol (the system tints it for light, dark and Reduce Transparency), with the battery percentage beside it in the system font.
- No colour in the menu bar.

## Panel

- **Page and card:** an off-white page (`#FAFAFA`) holding one white card with a 1 pt light-grey border (`#E5E7EB`), 12 pt corners and no shadow. Inside the card, settings are grouped into white rows with the same hairline border and 8 pt corners.
- **One accent:** blue `#2563EB`. It's used for switches, sliders, the primary button, and the thin battery strip along the top edge.
- **Tags:** small rounded labels in a pale tint with matching text. Blue is for facts (connection, DPI), green for good news (charging, healthy battery), and red for problems (not connected, low battery).
- **Chips:** a bordered pill holding a dark label plus a tag, used for the battery in the top bar.
- **Typography:** the system font. The heading is 18 pt bold in near-black (`#111827`). Row titles are 13 pt semibold, body text 12 pt grey (`#6B7280`), and notes 11 pt grey, with warnings in orange.
- **Icons:** thin SF Symbols in grey beside row titles, plus a chevron after pop-up values.
- **Buttons:** a ghost outlined button for the quiet action (Quit), a pale-blue button for secondary actions (Check for updates), and filled blue only for the one thing worth doing now (Install update).
- **Words:** sentence case and short labels. A note at the bottom says changes save automatically.

## Sources

- The look is based on a reference screenshot Alex shared (a clean light web app).
- Menu bar item rules: [Designing macOS menu bar extras](https://bjango.com/articles/designingmenubarextras/) (Bjango).
