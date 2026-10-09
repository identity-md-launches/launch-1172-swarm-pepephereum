# Swarm PEPEPHEREUM website design

## Overview

This one-page site introduces $SPEPE, explains its fixed mechanics and directs readers to the launch's trading page when its address exists. It adapts the [SIMD meme template](https://www.si-md.xyz/site-templates/meme/): a beige hardware-panel wall, black central terminal, green signal accents, LCD readouts and modular information panels. The supplied mascot anchors the hero. Its copper hair supplies the secondary accent.

The source of truth is `site/index.html`, `site/styles.css`, `site/app.js` and `site/coin-data.js`. `dist/` is a byte-identical runtime copy. The terminal comes first, followed by market readouts, buying instructions, lore and tokenomics. Hardware decorations are static and hidden from assistive technology; they do not pretend to be functional knobs or live market charts.

## Colors

The existing template's hex notation is retained. Implemented tokens live in `site/styles.css:4`.

| Token | Value | Role |
| --- | --- | --- |
| `--panel` | `#d9d6cc` | Opaque beige panels beneath text |
| `--panel-raised` | `#e8e4d9` | Copy button, step numbers, small raised surfaces |
| `--panel-inset` | `#c9c5b8` | Rack labels and unavailable Copy surface |
| `--ink` / `--muted` | `#191c18` / `#53564d` | Main / supporting text on beige |
| `--line` | `#33372e` | Hardware structure and hard shadows |
| `--screen` / `--screen-raised` | `#0c100d` / `#141c16` | Terminal, LCDs / terminal strips and secondary action |
| `--screen-line` | `#344239` | Internal screen separators |
| `--screen-text` / `--screen-muted` | `#e9efe6` / `#a3b5a4` | Main / supporting text on dark surfaces |
| `--signal` | `#3cff7a` | Ticker, LCD values, active Buy fill, dark-surface focus |
| `--signal-hover` / `--signal-dark` | `#a1ffbf` / `#143c22` | Buy hover / pending Buy and its depth |
| `--copper` / `--copper-ink` | `#cb8e50` / `#744117` | Logo-derived accent on dark / beige surfaces |
| `--focus` | `#00682b` | Keyboard focus against beige |

Copper denotes the mascot's identity and the pending badge; green follows the requested signal language. Status is always written out. Interactive elements have recognizable borders, underlines or button shapes. There is one filled primary trading action; Chart is secondary. There is no theme toggle or separate dark theme.

Measured examples: muted text on beige 5.15:1; copper text on beige 5.75:1; green on the screen 14.40:1; the beige-surface focus ring 4.79:1. The disabled Copy label measures 4.33:1 and is an inactive control. Methods and remaining limits are in `docs/site-review/contrast.json` and the validation report.

## Typography

Local WOFF2 files live in `site/assets/fonts/`, with OFL notices alongside them. Inter is a variable font supporting weights 100–900; IBM Plex Mono has real 400 and 600 faces. Both use `font-display: swap`. The browser confirmed all three files loaded.

- `--sans`: Inter, system-ui, sans-serif. Body base is 16 px, weight 500, line-height 1.6. Dense instructional and supporting copy is 14 px with 1.6–1.65 leading and measures around 50–58 characters, matching the hardware-panel layout.
- `--mono`: IBM Plex Mono, ui-monospace, monospace. Used for navigation, labels, ticker, contract address and numbers. Numerals that change use `tabular-nums`.
- Semantic base sizes are `--label: .75rem`, `--small: .875rem`, `--body: 1rem` and `--heading: 1.25rem`. Equipment captions use .625rem; they are subordinate to the main content and controls.
- The main name uses Inter 900, `clamp(1.9rem,4.2vw,3.375rem)`, 1.08 leading and −.055em tracking on wide screens. “Swarm” is a smaller line within the single H1. The mobile name uses `clamp(1.5rem,6.8vw,2.625rem)`.
- The ticker uses mono 600 at 2rem on wide screens; module titles use mono 600 at .875rem. The lore statement is Inter 900 at 2.375rem with 1.1 leading. Section numbers and captions use modest positive tracking and CSS uppercase.

Long names and addresses wrap rather than truncate. Full market values accompany compact visual readouts in screen-reader text and the title attribute. Tiny prices use scientific notation rather than a false zero. There is no continuously blinking cursor or typewriter animation.

## Layout

`main` is capped at 1180 px; the header/footer at 1280 px. The wall has 24 px outer padding, reducing to 16 px on small screens. Repeated gaps are 8, 12, 16, 20, 24, 28 and 32 px. Major panel groups are separated by 26–30 px. The desktop hero has a 310 px image column, flexible text column, 42 px gap and 40 px side padding. `minmax(0, …)` allows content to shrink.

| Breakpoint in `site/styles.css` | Adaptation |
| --- | --- |
| Above 66rem | Four LCD modules; two information columns; 310 px portrait column |
| At 66rem | Two LCD columns; 250 px portrait column; tighter gaps |
| At 48rem | Header wraps; modules become one column; portrait column becomes 190 px; tokenomics stacks; address details become one column |
| At 36rem | Hero stacks; portrait is 208 px; volume/address occupy full LCD rows; tax grid becomes two columns; text and controls remain inset |

Native hash navigation follows DOM order. All meaningful content is in normal document flow; there is no sticky bar or overlay. Addresses remain fully visible and selectable. Buttons permit long labels to wrap and grow. Tested layouts had no horizontal overflow at 320, 390, 576, 720, 768, 900, 1060 and 1440 CSS pixels. The 390 px layout also passed 200% CSS text enlargement with long feed names/symbols. This does not establish native browser zoom coverage.

## Elevation & Depth

`.panel` uses a 1 px structural border and `4px 4px 0 #33372e` hard shadow. The terminal has a 6 px frame and a 6 px offset hard shadow. Inset LCDs have a 2 px frame. Small screw pseudo-elements, patch ports, a static dial and the background artwork carry the hardware character. Decorative layers have `pointer-events: none` where they overlay content.

Text stays on opaque surfaces above the wall image. The slight grid overlay is decorative; it is not placed over reading panels. The only high stacking layer is the skip link when focused.

## Shapes

Panels are rectangular. The terminal uses a 4 px corner radius; controls 2 px; the scope 3 px. Circular geometry is reserved for the mascot crop, status lights, screws, ports and the dial. The mascot has a copper ring, a subtle white outline and a square instrument mount with green corner marks. Its natural 1:1 dimensions reserve layout space before loading.

## Components

| Pattern | Source / variants | States and behavior |
| --- | --- | --- |
| `.bar`, `.brand`, `nav` | `site/index.html:17`, CSS header rules | Three real hash links; 44 px minimum navigation height; wrap on mobile |
| `.terminal`, `.specimen`, `.hero-copy` | `site/index.html:32` | Local default logo; valid live `logo` preferred; failed replacements restore the local image |
| `.button.primary`, `.button.secondary` | `site/styles.css:62` | Pending anchors have no `href`, a dashed border and `aria-disabled`; valid feed URLs restore native link behavior. Buy and Chart each require the deployed token. No guessed destinations |
| `.lcd`, `.readout`, `.contract-row` | `site/index.html:67`, `site/app.js:64` | Missing values use an em dash; copy disabled without an address; full address wraps. All market labels remain stable during updates |
| Feed controls / status | `site/app.js:91` | Initial, fetching, awaiting launch, connected and failed/stale states; manual recovery; stable polite announcement region |
| Copy button | `site/app.js:127` | 44 px target; actual clipboard write with success feedback; denial selects the visible address and explains manual copying |
| `.module`, `.module-heading`, `.steps` | `site/index.html:78` | Opaque information panels with numeric labels and semantic headings/list |
| `.scope` | `site/index.html:95` | Static decorative waveform, explicitly “Signal study”; not a price chart |
| `.allocation`, `.tax-grid` | `site/index.html:104` | Written 90/10 allocation with an accessible description; tax figures use definition-list semantics |
| `.contract-details` | `site/index.html:109` | Native `details`/`summary`; keyboard opening/closing; full immutable addresses in normal flow |

Focus uses a 3 px ring, offset 4 px on beige and 5 px in the terminal. Buttons have hover, pending, focus and active states. Motion is limited to 150 ms transitions with `cubic-bezier(.2,0,0,1)` and a `.96` press scale, only under `prefers-reduced-motion: no-preference`. Reduced motion removes those transitions. Forced colors uses system colors and keeps structural borders/focus visible.

## Do's and Don'ts

- Reuse `.panel`, `.module-heading` and the established typography for another information section. Add a semantic heading and matching hash link; let the existing grid collapse naturally.
- Keep signal green exact. Use the copper pair appropriate to the background. Put prose on opaque beige or screen surfaces.
- Keep decorative hardware static and outside the accessibility tree. A decorative waveform must never imply live price performance.
- Continue using native links, buttons and disclosures. Preserve the visible focus ring and full contract address.
- Route all launch-specific identity, token addresses and trading destinations through the feed validator. Never ship an example address or invented quote in the export.
- Do not introduce autoplay, wallet infrastructure, forms, trackers, an unrequested theme, return claims, audit claims or partnership claims.
- Rebuild `dist/` after runtime edits; retain all local fonts/images and their licenses.

Design review used the pinned Better Interface guidance by Jakub Krehel (MIT). The documentation method adapts Paul Bakaus's Impeccable document guide (Apache-2.0). Attribution and both licenses are retained in `docs/licenses/better-interface.txt`; implementation-specific text above is newly written.
