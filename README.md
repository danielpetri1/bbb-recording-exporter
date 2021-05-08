
  

# BigBlueButton Exporter

⚠️ **Still a work in progress!** ⚠️<br  />

A client- and (future) server side script to enable users to download a BigBlueButton recording as a single video file.

This is still a work in progress that downloads Big Blue Button's `shapes.svg` file to locally recreate the recording played in the browser as a `webm` or `.mp4` file.

## What's supported?

✅ Export of BigBlueButton presentations containing audio, slides and whiteboard annotations<br  />
✅ Option to render the webcams and screen sharings (deskshare) in addition to the presentation<br  />
✅ Saving annotated slides as PNG so they can be merged into a new PDF<br  /> 

## What's coming?

🔜 Integration into Greenlight's UI<br  />

🔜 Conversion of annotated slides into PDF using Cairo<br  />

🔜 Support of further interactive elements such as the cursor, chat, and polls<br  /> 

🔜 Speed improvements<br  />


## Usage
In your terminal, type

    ruby download_client.rb "URL_OF_YOUR_BBB-RECORDING"

Create the presentation with

    ruby render_slides.rb

and the whiteboard with

    ruby render_whiteboard.rb

To then render the video, run

    ruby render_video.rb

If you want to get the slides with the whiteboard annotations

    ruby export_annotated_slides.rb

and open the 'slides' folder.

### Requirements
librsvg<br />
ffmpeg  version 4.4, compiled with --enable-librsvg <br />
Ruby with Nokogiri, open-uri, cgi, and fileutils<br />

Only tested and developed on macOS Big Sur so far for BBB 2.3 recordings. <br />

## How it works

The script creates an SVG frame for every timestep in the recording and uses [FFmpeg's Concatenate](https://trac.ffmpeg.org/wiki/Slideshow) format to render the animation as a slideshow. This requires FFmpeg 
to have been compiled with the `librsvg` option enabled.

In contrast to other approaches, this script is **not** dependent on headless browsers, screen recorders, and open source video editors... just plain Ruby to generate well-formed SVGs, hoping to get faster
render times and smaller file sizes.

The end goal is to integrate this script in Greenlight's GUI with further customization options, such as allowing trimming, downloading the annotated slides as a PDF, choosing the desired resolution and so on.