# DevourCMD
OCR Cue Detection in Vor Files to Add Chapter Markers

This is a commandline tool to read Eos cue markers from a video made in VOR, and write them as chapter markers into a movie file.
```
Usage: path [x y h w skipframes]
Usage: path is the movie file to scan
Usage: (x, y, h, w) are normalized CGRect values to scan for text.  Origin is bottom left.  Smaller is better.  Defaults to full frame
Usage: skipframes is how many frames to skip in between scanning a frame.  Try 15 (which is the default)
```

Currently, Devour is hardwired to look for a string like "Cue XX.XX", where XX is a number, and the point cue is optional.  

Setting a Region Of Interest greatly increases the speed of the OCR, and stops other text from being recognized (video or automation cues, if you are capturing those as well).

Setting "skipframes" causes OCR recognition to skip frames between looking for cue tags.  Theoretically you could miss cues in scanning if they exist for less than the number of skipframes, but the scanning speed up of using 15 or 30 frames as a skip value is sizable and I think worth it.

In Quicktime Player, you can use CMD+SHIFT+ARROWS to jump between chapter markers, or in the player controls there is a option to open a menu of the chapter markers that you can scroll and click on.  
