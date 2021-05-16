
  

# BigBlueButton Exporter

⚠️ **Still a work in progress!** ⚠️<br  />

A client- and (future) server side script to enable users to download a BigBlueButton 2.3-dev recording as a single video file.

This is still a work in progress that downloads Big Blue Button's `shapes.svg` file to locally recreate the recording played in the browser as a `.mp4` file.

## What's supported?

✅  Whiteboard slides with annotations <br  />
✅  Webcams <br  />
✅  Screen shares <br  />
✅  Polls <br  />
✅  Cursor <br  />
✅  Saving annotated slides as PNG so they can be merged into a new PDF<br  />

## What's coming?

🔜 Integration into Greenlight's UI<br  />

🔜 Conversion of annotated slides into PDF using Cairo<br  />

🔜 Support of further interactive elements such as the chat, text and panzooms <br  /> 


## Usage
In the `download_client.rb` file, change the `path` variable to reflect your BBB recording link like so:
    
    path = "https://hostname/presentation/meetingID/#{file}"

Make sure to adapt the array beginning with `shapes.svg` to reflect your recording, changing file extensions and removing the deskshare if necessary.
Run with

    ruby download_client.rb

Render the presentation and the whiteboard with

    ruby render_whiteboard.rb

and the whiteboard with

    ruby render_whiteboard.rb

To then render the video, run

    ruby render_video.rb

If you want to get the slides with the whiteboard annotations (currently still requires librsvg)

    ruby export_annotated_slides.rb

and open the 'slides' folder.

### Requirements
ffmpeg  version 4.4, compiled with --enable-librsvg <br />
Ruby with Nokogiri, open-uri, cgi, and fileutils<br />

Only tested and developed on macOS Big Sur so far for BBB 2.3 recordings. <br />

## How it works

The script creates an SVG frame for every timestep in the recording and uses [FFmpeg's Concatenate](https://trac.ffmpeg.org/wiki/Slideshow) format to render the animation as a slideshow. This requires FFmpeg 
to have been compiled with the `librsvg` option enabled.

In contrast to other approaches, this script is **not** dependent on headless browsers, screen recorders, and open source video editors... just plain Ruby to generate well-formed SVGs, hoping to get faster
render times and smaller file sizes.

The end goal is to integrate this script in Greenlight's GUI with further customization options, such as allowing trimming, downloading the annotated slides as a PDF, choosing the desired resolution and so on.
