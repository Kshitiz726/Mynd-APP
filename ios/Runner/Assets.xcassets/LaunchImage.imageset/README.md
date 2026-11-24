# LaunchImage

The mark shown on the launch screen, before Flutter has drawn a frame.

These used to be Flutter's placeholder files: 68-byte transparent 1x1 PNGs.
The storyboard dutifully centred them, so every cold start showed a blank
white screen for as long as the engine took to boot, which on a cold launch
is a second or more of nothing.

They are generated from `assets/branding/app_icon.png`, clipped to Apple's
icon corner radius (22.37% of the side) so the mark on the launch screen is
the same object the user just tapped. 128pt at 1x/2x/3x.

To regenerate after the icon changes, see the Swift snippet in the commit that
added this file, or simply resize and round-corner the source to
128/256/384px.
