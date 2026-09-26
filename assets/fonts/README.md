# Print font

`TierPrintSans-Regular.ttf` is a static weight-400 instance of Noto Sans SC,
renamed **MuBangumi Print Sans** to distinguish this derived build.

- Source: https://github.com/notofonts/noto-cjk/blob/main/Sans/Variable/TTF/Subset/NotoSansSC-VF.ttf
- Original source SHA-256: `d68bafcb48a2707749396aa12bbbd833cb70401f3a9a689fd2902c7e0d295964`
- Derived with fontTools 4.60.1 `instantiateVariableFont(..., {'wght': 400})`.
- Name IDs 1/2/3/4/6/16/17 identify the derived family; original copyright metadata remains.
- License: SIL Open Font License 1.1, included as `OFL.txt`.

The font is loaded only when exporting the experimental print kit. It is bundled
to keep Chinese/Japanese labels printable without downloading fonts at export
time. Glyphs outside its character coverage are represented as a square in PDF
labels; subject IDs and links remain available in the index.

`TierPrintHangul-Regular.ttf` supplements Hangul syllables and Jamo from the same
Noto project, also under the included OFL. It is a weight-400 instance of
`Sans/Variable/TTF/Subset/NotoSansKR-VF.ttf`, subset to U+AC00-D7A3,
U+1100-11FF and U+3130-318F. Source SHA-256:
`9e1d729e7e2b36f9ef439da102f8c134c10aabe46f1c843bf0aca5c043b86f76`.
It is renamed MuBangumi Print Hangul; original copyright metadata remains.
PDF uses this as a fallback, without altering the Chinese/Japanese font.
