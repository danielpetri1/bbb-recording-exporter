
  

# BigBlueButton Exporter

  

Server-side version of the script that enables users to download BigBlueButton 2.3 recordings as a single video file.

  

## What's supported?

  

✅ Annotations <br  />

✅ Chat <br  />

✅ Cursor <br  />

✅ Polls <br  />

✅ Screen shares <br  />

✅ Slides<br  />

✅ Text <br  />

✅ Webcams <br  />

✅ Zooms <br  />

  

![BigBlueButton recording exporter](/demo/export_example.png)

  

## Server-Side Usage

Begin by installing Loofah on your BigBlueButton server: `gem install loofah`

Place the file `export_presentation.rb` in the `/usr/local/bigbluebutton/core/scripts/post_publish` directory with executable rights.
  
Do the same for the file `lib/interval_tree.rb`, moving it to `/usr/local/bigbluebutton/core/lib/recordandplayback`.

After a session is over and the presentation is processed, the script will begin to export the recording as a single video file. It can be accessed and downloaded at https://`your.bbb.hostname`/presentation/`meeting-id`/meeting.mp4 once rendering completes.

The meeting's ID is the alphanumeric string following the 2.3 in the recording's URL.

Existing recordings can be rebuilt to run the exporting scripts automatically again:

    ./export_presentation.rb -m <meeting_id>

To re-render all existing recordings, run

    bbb-record --rebuildall

If you do not have access to a BBB server, check out the branch 'client-side'.

To add a download button to Greenlight's UI, change  [these](https://github.com/danielpetri1/greenlight/commit/72c2165e4a504aa40e116a83864de36dea540b65)  files.

### Requirements

  

FFmpeg compiled with `--enable-librsvg` and `--enable-libx264`  <br  />

Ruby with the Nokogiri and Loofah gems installed <br  />

  

### Rendering options

If your server runs BBB 2.2 or earlier, it is advised to set the flag `REMOVE_REDUNDANT_SHAPES` to **true** in `render_whiteboard.rb`. This will ensure the live whiteboard feature is still supported, require less storage space and increase rendering speeds.

Less data can be written on the disk by turning `SVGZ_COMPRESSION` on.

To make rendering faster and less resource-intensive, download FFMpeg's source code and replace the file `ffmpeg/libavcodec/librsvgdec.c` with the one in this directory. After FFmpeg is compiled and installed, enable `FFMPEG_REFERENCE_SUPPORT` in `render_whiteboard.rb`.

The video output quality can be controlled with the `CONSTANT_RATE_FACTOR`.

### Get in touch

If this code helped you or you encountered any problems, please do get in touch! Since this script is being actively developed for my bachelor's Thesis at the Technical University of Munich, feedback is more than welcomed. It will be provided here as documentation.