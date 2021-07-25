
# BigBlueButton Exporter

Client-side version of the script to export the recorded presentation as a single PDF file.

## Client Side Usage

In the `download_client.rb` file, change the `path` variable to reflect your BBB recording link like so:

    path = "https://hostname/presentation/meetingID/#{file}"

Run with

    ruby download_client.rb

Export the PDF with

    ruby export_slides.rb

The resulting file `annotated_slides.pdf` can then be found in the script's directory.

### Requirements

librsvg <br  />
combine_pdf gem <br  />

###  Rendering options 
If your server runs BBB 2.2 or earlier, it is advised to set the flag `REMOVE_REDUNDANT_SHAPES` to **true** in `export_slides.rb`.
Less data can be written on the disk by turning `SVGZ_COMPRESSION` on.

###  Get in touch
If this code helped you or  you encountered any problems, please do get in touch! Since this script is being actively developed for my bachelor's Thesis at the Technical University of Munich, feedback is more than welcomed.