
# BigBlueButton Whiteboard Downloader

A client- and (future) server side script to generate BigBlueButton recordings.

This is still a work in progress that downloads Big Blue Button's `shapes.svg` file and locally recreates the presentation slides and annotations made during the session as a `webm` or `.mp4` file with audio.

## What's supported?

✅  Exporting BigBlueButton presentations as a single video file, including audio, slides and whiteboard annotations
✅  Saving annotated slides as PNG so they can be merged into a new PDF

## What's coming?

🔜  Option to add the session's webcams <br />
🔜  Option to add the session's screen sharing video (deskshare) <br />
🔜  Cursor support <br />
🔜  Chat, polls <br />

## How it works


The script creates an SVG frame for every timestep in the recording and uses [FFmpeg's Concatenate](https://trac.ffmpeg.org/wiki/Slideshow) format to render the animation as a slideshow. Currently this prototype still exports the SVG files as intermediate PNG files, thus being dependent on `librsvg`, but FFmpeg can be compiled with `-enable-librsvg` to skip this step entirely.

In contrast to other approaches, this script is **not** dependent on headless browsers, screen recorders, open source video editors... just plain Ruby to generate well-formed SVGs. Since the generated video has a variable frame rate, rendering happens blazing fast and results in very small file sizes.

The end goal is to integrate this script in Greenlight's GUI with further options such as allowing the students and teachers to add webcams, screen recordings (deskshare), trim the file given start- and end times, download the annotated slides as a PDF with Cairo, choosing the desired resolution and so on.
