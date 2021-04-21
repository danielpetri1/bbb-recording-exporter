
# BigBlueButton Downloader

A client- and (future) server side script to enable users to download a BigBlueButton recording as a video.

This is still a work in progress that downloads Big Blue Button's `shapes.svg` file to locally recreate the recording played in the browser as a `webm` or `.mp4` file.

## What's supported?

✅  Quick export of BigBlueButton presentations as a single video file, containing audio, slides and whiteboard annotations<br />
✅  Rendering BigBlueButton sessions into a video that includes the whiteboard, audio and screen sharing video (deskshare)<br />
✅  Saving annotated slides as PNG so they can be merged into a new PDF<br />

## What's coming?

🔜  Option to add the session's webcams <br />
🔜  Cursor support <br />
🔜  Chat, polls <br />

## How it works

The script creates an SVG frame for every timestep in the recording and uses [FFmpeg's Concatenate](https://trac.ffmpeg.org/wiki/Slideshow) format to render the animation as a slideshow. This is achieved by exporting the SVG frames as intermediate PNG files using `librsvg`, which in turn allows the final annotated slides to be saved separately as well.

In contrast to other approaches, this script is **not** dependent on headless browsers, screen recorders, open source video editors... just plain Ruby to generate well-formed SVGs. Since the generated video has a variable frame rate, rendering happens blazing fast and results in small file sizes.

The end goal is to integrate this script in Greenlight's GUI with further options such as allowing the students and teachers to add webcams, screen recordings (deskshare), trim the file given start- and end times, download the annotated slides as a PDF with Cairo, choosing the desired resolution and so on.
