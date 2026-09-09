#!/usr/bin/env python3
"""Package the existing universal app ZIP as a styled drag-and-drop DMG."""
from pathlib import Path
import argparse
import plistlib
import subprocess
import tempfile

import dmgbuild
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = '/System/Library/Fonts/Supplemental/Arial.ttf'
BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'


def background(path):
    # Render at 2x, then attach physical dimensions for a 720x480 Finder window.
    scale = 2
    im = Image.new('RGB', (720 * scale, 480 * scale))
    d = ImageDraw.Draw(im)
    for y in range(im.height):
        t = y / im.height
        d.line((0, y, im.width, y), fill=tuple(int(a+(b-a)*t) for a,b in zip((16,27,48),(23,47,57))))
    def text(x,y,value,size,color,bold=False):
        d.text((x*scale,y*scale),value,font=ImageFont.truetype(BOLD if bold else FONT,size*scale),fill=color)
    text(44,30,'TERMINAL FIRST',14,'#75e2bc',True)
    text(44,62,'Your terminal. One shortcut away.',30,'#f2f7ff',True)
    text(44,108,'Drag Terminal First into Applications to install.',17,'#bacddd')
    # Quiet light platforms keep Finder's dark icon labels readable in either theme.
    for x in (112,448):
        d.rounded_rectangle((x*scale,168*scale,(x+160)*scale,325*scale),radius=20*scale,fill='#eef3f7')
    d.line((316*scale,226*scale,401*scale,226*scale),fill='#75e2bc',width=3*scale)
    d.line((389*scale,214*scale,401*scale,226*scale,389*scale,238*scale),fill='#75e2bc',width=3*scale)
    d.rounded_rectangle((584*scale,343*scale,706*scale,476*scale),radius=14*scale,fill='#eef3f7')
    text(44,357,'Then open it from Applications.',19,'#f2f7ff',True)
    text(44,389,'Find the shortcut controls in your menu bar.',15,'#bacddd')
    text(44,444,'macOS 13+  /  Intel + Apple Silicon',12,'#91aaba')
    im.save(path, dpi=(144,144))


def app_icon(path):
    im = Image.new('RGBA',(1024,1024))
    d=ImageDraw.Draw(im)
    d.rounded_rectangle((60,60,964,964),radius=205,fill='#142637')
    d.rounded_rectangle((138,184,886,823),radius=78,fill='#0a1421',outline='#496072',width=9)
    d.line((142,306,882,306),fill='#334b5c',width=9)
    for x,c in [(203,'#ff766f'),(257,'#ffd078'),(311,'#75e2bc')]:
        d.ellipse((x-14,245-14,x+14,245+14),fill=c)
    d.line((235,424,355,532,235,640),fill='#75e2bc',width=40)
    d.rounded_rectangle((417,617,592,650),radius=10,fill='#75e2bc')
    d.text((668,397),'1',font=ImageFont.truetype(BOLD,240),fill='#f2f7ff')
    im.save(path,format='ICNS')


def run(*args):
    subprocess.run(args,check=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-zip',type=Path,default=ROOT/'Terminal First App.zip')
    parser.add_argument('--output',type=Path,default=ROOT/'Terminal-First.dmg')
    args=parser.parse_args()
    archive=args.app_zip.resolve()
    output=args.output.resolve()
    if not archive.is_file():
        parser.error('Build the app first with bash Source/build.sh')
    if output.exists():
        parser.error(f'Output already exists: {output}; choose a new output path.')
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='terminal-first-dmg-',dir='/tmp') as directory:
        stage=Path(directory)
        run('ditto','-x','-k',str(archive),str(stage))
        app=stage/'Terminal First.app'
        resources=app/'Contents/Resources'
        resources.mkdir(exist_ok=True)
        icon=resources/'AppIcon.icns'
        app_icon(icon)
        info=app/'Contents/Info.plist'
        data=plistlib.loads(info.read_bytes())
        data['CFBundleIconFile']='AppIcon'
        info.write_bytes(plistlib.dumps(data))
        run('codesign','--force','--sign','-',str(app))
        run('codesign','--verify','--deep','--strict',str(app))
        bg=stage/'background.tiff'
        background(bg)
        instructions=stage/'First Open.txt'
        instructions.write_text('''TERMINAL FIRST — FIRST OPEN

1. Drag Terminal First into Applications.
2. Open Terminal First from Applications.
3. If macOS blocks it, and you trust this copy, go to:
   System Settings > Privacy & Security > Open Anyway.
   Confirm the prompt. This build is not Apple-notarized.
4. Look for the Command + 1 control in your menu bar.
5. Press Command + 1 to open or focus Apple Terminal.

Choose Start at Login if you want it available after you sign in.
Pause or Quit releases the shortcut for other apps.
Eject this disk image after copying the app.

Requires macOS 13 or later. Works on Intel and Apple Silicon.
No Accessibility or Input Monitoring permissions are needed.
Company-managed Macs may restrict apps that are not notarized.

If another global hotkey tool already owns Command + 1, disable
that binding before enabling Terminal First.

To uninstall: turn off Start at Login, quit, and trash the app.
''')
        dmgbuild.build_dmg(str(output),'Terminal First',settings={
            'format':'UDZO','filesystem':'HFS+',
            'files':[str(app),str(instructions)],'symlinks':{'Applications':'/Applications'},
            'icon':str(icon),'background':str(bg),
            'window_rect':((160,160),(720,480)),
            'icon_locations':{'Terminal First.app':(192,230),'Applications':(528,230),'First Open.txt':(645,402)},
            'icon_size':80,'text_size':13,
            'default_view':'icon-view','show_status_bar':False,'show_tab_view':False,
            'show_toolbar':False,'show_pathbar':False,'show_sidebar':False,
        })
    run('hdiutil','verify',str(output))
    print(f'Created {output}')


if __name__=='__main__':
    main()
