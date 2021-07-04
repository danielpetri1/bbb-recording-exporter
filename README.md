
# BigBlueButton Exporter

Client-side version of the script that enables users to download BigBlueButton 2.3 recordings as a single video file.

  

## What's supported?

✅  Annotations <br  />
✅ Chat <br  />
✅ Cursor <br  />
✅ Polls <br  />
✅ Screen shares <br  />
✅ Slides<br  />
✅ Text <br  />
✅ Webcams <br  />
✅ Zooms <br  />

![BigBlueButton recording exporter](/slides/export_example.png)

## Client Side Usage

In the `download_client.rb` file, change the `path` variable to reflect your BBB recording link like so:

    path = "https://hostname/presentation/meetingID/#{file}"

Make sure to adapt the array beginning with `shapes.svg` to reflect your recording's data, changing file extensions and removing the deskshare if necessary.

Run with

    ruby download_client.rb

Render the presentation, whiteboard, mouse pointer and chat with

    ruby render_chat.rb
    
    ruby render_cursor.rb
    
    ruby render_whiteboard.rb


### Requirements


FFmpeg compiled with `--enable-librsvg` <br  />

Ruby with Nokogiri<br  />

###  Rendering options 
If your server runs BBB 2.2 or earlier, it is advised to set the flag `REMOVE_REDUNDANT_SHAPES` to **true** in `render_whiteboard.rb`. This will ensure the live whiteboard feature is still supported, require less storage space and increase rendering speeds.

Less data can be written on the disk by turning `SVGZ_COMPRESSION` on.

To make rendering faster and less resource-intensive, download FFMpeg's source code and replace the file `ffmpeg/libavcodec/librsvgdec.c` with the one in this directory. After compiling and installing FFMpeg,  enable `FFMPEG_REFERENCE_SUPPORT` in `render_whiteboard.rb` .

After rendering of the mp4 file completes, the `frames` folder can be deleted in order to save server storage space.

###  Get in touch
If this code helped you or  you encountered any problems, please do get in touch! Since this script is being actively developed for my Bachelor's Thesis at the Technical University of Munich, feedback is more than welcomed.