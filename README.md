
  

# BigBlueButton Exporter

Server-side version of the script that exports recorded presentation slides as a single PDF file.


## What's supported?

  

  

✅  Annotations <br  />


✅  Integration with Greenlight <br  />


✅  Polls <br  />
  

✅  Slides<br  />


✅  Text <br  />
  

## Server-Side Usage

Place the file `export_slides.rb` in the `/usr/local/bigbluebutton/core/scripts/post_publish` directory with executable rights.
  
Do the same for the file `lib/interval_tree.rb`, moving it to `/usr/local/bigbluebutton/core/lib/recordandplayback`.

After a session is over and the presentation is processed, the script will begin to export the recording as a single PDF file. It can be accessed and downloaded at `https://<your.bbb.hostname>/presentation/<meeting-id>/annotated_slides.pdf` once rendering completes, or directly in the Greenlight interface.

The meeting's ID is the alphanumeric string following the 2.3 in the recording's URL.

Existing recordings can be converted into PDF by running the exporting script on an individual basis:

    ./export_slides.rb -m <meeting_id> -f presentation

To convert all existing recordings, run

    bbb-record --rebuildall

If you do not have access to a BBB server, check out the branch 'pdf-export-client'.

### Requirements
librsvg (`sudo apt-get install librsvg2-bin`)
combine_pdf gem (`gem install combine_pdf`)

Root access to a BBB 2.3 server.

###  Rendering options 
If your server supports animated strokes on the whiteboard, set the flag `REMOVE_REDUNDANT_SHAPES` to **true** in `export_presentation.rb`.

Less data can be written on the disk by turning `SVGZ_COMPRESSION` on.

### Troubleshooting

  

Exports don't start after the meeting ends: `/var/log/bigbluebutton/post_publish.log` and `/var/bigbluebutton/published/document/` must be chowned to `bigbluebutton:bigbluebutton`

  



### Get in touch



If this code helped you or you encountered any problems, please do get in touch! This script was developed for my [bachelor's thesis](https://mediatum.ub.tum.de/doc/1632305/1632305.pdf) at the Technical University of Munich, so feedback is welcomed.
