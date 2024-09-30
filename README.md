# Devour
OCR Cue Detection in Vor Files to Add Chapter Markers
*Requires Mac OS Sequoia (15.0) or newer.  Tested on Apple Silicon only.*

This project has been built to add chapter markers into show recordings made by Vor (or any other show recording solution), based on changes in the current cue.  There is a GUI app, Devour, and also a command-line version DevourCMD.

Devour uses a "region of interest" (ROI) as the area to search for OCRing the cue number.  The cue number is recognized as the number that comes after the word "Cue " or "CUE " (notice the space).  Limiting the ROI as small as possible will speed up scanning and prevent false positives (from other lines of text in the recording).  

Output files default to the name/path of the original file with "_devoured" tagged onto the end.  In Quicktime Player, you can use CMD+SHIFT+ARROWS to jump between chapter markers, or in the player controls there is a option to open a menu of the chapter markers that you can scroll and click on.  
For one act of a "typical" Broadway musical it took about 4 minutes to scan, process, and output the new file.

The commandline tool has the following usage
```
Usage: path [x y h w ]
Usage: path is the movie file to scan
Usage: (x, y, h, w) are normalized CGRect values to scan for text.  Origin is bottom left.  Smaller is better.  Defaults to full frame
```

## Disclaimer
This is a complete experiment of a project.  Assume no warranty and that it simply could stop working.  It has had very little testing and has been debugged to work on my machine, assuming it will then work everywhere.  But I'm happy to hear about bug reports and will endeavor to help where I can.
- Dan Scully / dan@danscully.com
