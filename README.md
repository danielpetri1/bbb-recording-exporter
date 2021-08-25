
  

# BigBlueButton Exporter

  

Server-side version of the script that enables users to download BigBlueButton 2.3 recordings as a single video file.

  

## What's supported?

  

✅ Annotations <br  />

✅ Captions <br  />

✅ Chapters <br  />

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

Place the file `export_presentation.rb` in the `/usr/local/bigbluebutton/core/scripts/post_publish` directory with executable rights.
  
Do the same for the file `lib/interval_tree.rb`, moving it to `/usr/local/bigbluebutton/core/lib/recordandplayback`.

After a session is over and the presentation is processed, the script will begin to export the recording as a single video file. It can be accessed and downloaded at https://`your.bbb.hostname`/presentation/`meeting-id`/meeting.mp4 once rendering completes.

The meeting's ID is the alphanumeric string following the 2.3 in the recording's URL.

Existing recordings can be re-rendered by running the exporting script on an individual basis:

    ./export_presentation.rb -m <meeting_id>

To re-render all existing recordings, run

    bbb-record --rebuildall

If you do not have access to a BBB server, check out the branch 'client-side'.

For caption support, recompile FFmpeg with the `movtext` encoder enabled and uncomment the `add_captions` method.

To add a download button to Greenlight's UI, change  [these](https://github.com/danielpetri1/greenlight/commit/d92f8502e3dacc87fb6ae6b05c91a2353010d884)  files.

### Requirements

Root access to a BBB 2.3 server.

###  Rendering options 
If your server supports animated strokes on the whiteboard, set the flag `REMOVE_REDUNDANT_SHAPES` to **true** in `export_presentation.rb`.

Less data can be written on the disk by turning `SVGZ_COMPRESSION` on.

To make rendering faster and less resource-intensive, download FFMpeg's source code and replace the file `ffmpeg/libavcodec/librsvgdec.c` with the one in this directory. After compiling and installing FFMpeg, enable `FFMPEG_REFERENCE_SUPPORT` in `export_presentation.rb` . [Steps by @felcaetano](https://github.com/danielpetri1/bbb-recording-exporter/issues/44#issuecomment-904464887).

The video output quality can be controlled with `CONSTANT_RATE_FACTOR`.

### Troubleshooting

Exports don't start after the meeting ends: `/var/log/bigbluebutton/post_publish.log` must be chowned to `bigbluebutton:bigbluebutton`
Captions 

### Get in touch

If this code helped you or you encountered any problems, please do get in touch! Since this script is being actively developed for my bachelor's Thesis at the Technical University of Munich, feedback is more than welcomed. It will be provided here as documentation.