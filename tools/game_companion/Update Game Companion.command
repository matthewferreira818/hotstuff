#!/bin/zsh
# The app is now called Friday; this old name still works. It just runs the new one.
exec zsh "${0:A:h}/Update Friday.command"
