![Cool logo](/img/cool-logo.png)

# Aseprite ASCII

Ever wanted to create ASCII art from yours inside Aseprite? This is it.

![](/img/img-example-2.png)

This extension allows you to:
- Preview your art
- Select from following glyph sets:
    - Standard ` .:-=+*#%@`
    - Detailed `` .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$``
    - Custom
- Define your resoultion with cell height and width
- You can copy or save .txt file, or even create new layer from that

## Usage

1. Download latest release from [releases page](https://github.com/egordunaev/aseprite-ascii/releases)
2. In Aseprite go to `Edit -> Preferences -> Extensions -> Add extension`
3. It should be auto enabled. ***For operations like copy ascii output to buffer it may ask additional permissions.***
4. To open ASCII window go to `View -> ASCII Art`

## Contributing

### Build

macOs/Linux

```bash
zip ascii-art.aseprite-extension package.json ascii.lua core.lua xp.lua
```

windows (powershell)
```powershell
Compress-Archive -Force package.json, ascii.lua, core.lua, xp.lua ascii-art.zip
Move-Item -Force ascii-art.zip ascii-art.aseprite-extension
```

### Test

Run from project folder (Replace `aseprtie` with full path to local executable if it's not on your PATH)
```
aseprite -b --script test.lua
```