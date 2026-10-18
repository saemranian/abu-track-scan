# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['DesktopSync\\camtrack_desktop_gui.py'],
    pathex=['DesktopSync'],
    binaries=[],
    datas=[],
    hiddenimports=['abu_clock_bridge'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['jinja2', 'markupsafe', 'setuptools', 'PIL._avif'],
    noarchive=False,
    optimize=1,
)
a.binaries = [
    b for b in a.binaries
    if not b[0].startswith('PIL\\_avif')
]
a.datas = [
    d for d in a.datas
    if not d[0].startswith(('_tcl_data\\tzdata', '_tcl_data\\msgs', '_tk_data\\msgs', 'matplotlib\\mpl-data\\sample_data'))
]
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='abu_track_desktop',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
