
  

# BigBlueButton Exporter

⚠️ **Still a work in progress!** ⚠️<br  />

A client- and server side script to enable users to download a BigBlueButton 2.3-dev recording as a single video file.

This is still a work in progress that downloads Big Blue Button's `shapes.svg` file to locally recreate the recording played in the browser as a `.mp4` file.

## What's supported?

✅  Whiteboard slides with annotations <br  />
✅  Webcams <br  />
✅  Screen shares <br  />
✅  Polls <br  />
✅  Cursor <br  />
✅  Zooms <br  />
✅  Text <br  />
✅  Chat <br  />

![BigBlueButton recording exporter](/slides/export_example.png)

## What's coming?

🔜 Integration into BBB and Greenlight's UI<br  />

## Usage
In the `download_client.rb` file, change the `path` variable to reflect your BBB recording link like so:
    
    path = "https://hostname/presentation/meetingID/#{file}"

Make sure to adapt the array beginning with `shapes.svg` to reflect your recording's data, changing file extensions and removing the deskshare if necessary.
Run with

    ruby download_client.rb

Render the presentation, whiteboard, mouse pointer and chat with

    ruby render_whiteboard.rb
    ruby render_cursor.rb
    ruby render_chat.rb

To then render the video, open the render_video.rb file and choose the appropriate FFmpeg command. Check whether the file extensions are correct once again.

    render_video.rb

### Requirements
ffmpeg  version 4.4, compiled with --enable-librsvg <br />
Ruby with Nokogiri<br />

Only tested and developed on macOS Big Sur so far for BBB 2.3 recordings. <br />

## How it works

The script creates a SVG frame for every timestep in the recording and uses [FFmpeg's Concatenate](https://trac.ffmpeg.org/wiki/Slideshow) format to render the animation as a slideshow. This requires FFmpeg 
to have been compiled with the `librsvg` option enabled, which is the case on BigBlueButton 2.3.

In contrast to other approaches, this script is **not** dependent on headless browsers, screen recorders, and open source video editors... just plain Ruby to generate well-formed SVGs, hoping to get faster
render times and smaller file sizes.

The end goal is to integrate this script in Greenlight's GUI with further customization options, such as allowing trimming, downloading the annotated slides as a PDF, choosing the desired resolution and so on.
