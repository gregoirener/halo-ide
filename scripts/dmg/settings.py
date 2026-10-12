# dmgbuild settings for Halo. Run via scripts/make-dmg.sh.
import os

application = defines["app"]
appname = os.path.basename(application)

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")
background = defines["background"]

window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
icon_size = 112
text_size = 13
icon_locations = {appname: (170, 200), "Applications": (490, 200)}
