# BigBlueButton Exporter

⚠️ **Still a work in progress!** ⚠️<br  />

Client-side version of the scripts to enable users to download a BigBlueButton 2.3-dev recording as a single video file.

## What's supported?

  

✅ Whiteboard slides with annotations <br  />

✅ Webcams <br  />

✅ Screen shares <br  />

✅ Polls <br  />

✅ Cursor <br  />

✅ Zooms <br  />

✅ Text <br  />

✅ Chat <br  />

![BigBlueButton recording exporter](/slides/export_example.png)

## Usage - Client Side

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

Choose an appropriate ffmpeg command in `render_video` and run it in the terminal. After rendering is complete, you can delete the contents of the created folders to save space.

### Requirements

ffmpeg version 4.4, compiled with --enable-librsvg <br  />

Ruby with Nokogiri<br  />