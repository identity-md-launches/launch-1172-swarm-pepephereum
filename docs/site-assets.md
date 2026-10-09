# Website asset provenance

All default runtime assets are bundled under `site/assets/` and copied unchanged to `dist/assets/`. The site makes no font or default-image request to a third-party server. The creator's future feed `logo` can specify a different HTTPS image.

| Asset | Source and preparation |
| --- | --- |
| `spepe.webp` | [Requester-supplied logo](https://fxumiqjngmabtgvruvka.supabase.co/storage/v1/object/public/forum-attachments/posts/mv10z989-nw554x.jpg), fetched 2026-10-09. The 1408×1408 original was resized to 640×640 and encoded as WebP at quality 88, effort 6 using Sharp 0.34.5. No content was generated or retouched. Circular cropping is CSS only. |
| `panels.webp` | [SIMD launchpad panel artwork](https://www.si-md.xyz/launchpad/panels.webp), used unchanged from the [requested meme template](https://www.si-md.xyz/site-templates/meme/), fetched 2026-10-09. 1840×400 WebP. |
| `ibm-plex-mono-400.woff2` | Fontsource CDN, `https://cdn.jsdelivr.net/fontsource/fonts/ibm-plex-mono@latest/latin-400-normal.woff2`, fetched 2026-10-09. The exact binary is bundled; rebuilding does not refetch `latest`. |
| `ibm-plex-mono-600.woff2` | Fontsource CDN, same family, `latin-600-normal.woff2`, fetched 2026-10-09. |
| `inter-latin-variable.woff2` | Fontsource CDN, `https://cdn.jsdelivr.net/fontsource/fonts/inter:vf@latest/latin-wght-normal.woff2`, fetched 2026-10-09. Variable weights 100–900, Latin subset. |

Font licenses were retrieved from the corresponding Google Fonts `ofl/ibmplexmono/OFL.txt` and `ofl/inter/OFL.txt` and are bundled alongside the fonts. Rebuilding is offline and copies the exact committed binaries. The local checksums below establish those inputs independently of moving CDN aliases.

```text
c54145658b5c8cd512cc628ffa9f2a15c31159376e185967dffe6f1751060a0d  spepe.webp
04b4b828018cfcecf1e5c9f25203a4bd101854da20098c3fe3d763aa66c96f55  panels.webp
08949f728dc52d528e69b1667d15c89a5686a4ee9a296ff90983985f99c380f7  fonts/ibm-plex-mono-400.woff2
0d1f0b8d0722224e32e9f28261bdc86c79115be73444ae5eceb73976a1bcdf83  fonts/ibm-plex-mono-600.woff2
3100e775e8616cd2611beecfa23a4263d7037586789b43f035236a2e6fbd4c62  fonts/inter-latin-variable.woff2
```

The new brand waveform, scope waveform and copy icon are small inline SVG paths. Dial, ports, screw heads and vents are CSS. No icon package is needed. The earlier contributor's five logo options in `logos/` remain unchanged and are not part of the website's runtime payload.
