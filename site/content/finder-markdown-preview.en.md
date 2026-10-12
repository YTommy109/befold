Selecting a file in Finder and pressing Space is a handy Mac habit. For a `.md` file, though, you get plain text: headings and tables show up as raw `#`, `|` and `-` characters. This article explains why, and how to keep using Space and still read the rendered result.

### Why it shows plain text

Finder's preview (QuickLook) knows how to draw each file type. It can draw images and PDFs, but it treats Markdown as a text file and shows the markup as it is. A diagram written in a ` ```mermaid ` code block is no different: you see the code, not the diagram.

Plenty of the time you only want to read. An AI-generated design doc, a README you just downloaded, a note on your disk. Launching an editor or a browser each time is a detour.

### Keep Space, get the rendered view

QuickLook accepts extensions, and befold ships one. Once it is installed, selecting a `.md` or `.mmd` file in Finder and pressing Space shows it rendered.

1. Download befold and put it in your Applications folder
2. In Finder, select a `.md` / `.mmd` file and press Space

Headings, tables and code blocks are formatted, and Mermaid blocks are drawn as diagrams. No app window opens.

### Good to know

- QuickLook renders only the one file you selected. It cannot read other files in the same folder, so images referenced by relative path may not appear there.
- Large text files are limited to 2 MB. Open anything bigger in the app.
- befold is for reading. It does not edit.

The full list of what befold does is on the [features page](/en/features).

### Try befold

{{cta}}
