
  

# BigBlueButton Downloader

  

⚠️ **Still a work in progress!** ⚠️<br  />

A client- and (future) server side script to enable users to download a BigBlueButton recording as a single video file.

This is still a work in progress that downloads Big Blue Button's `shapes.svg` file to locally recreate the recording played in the browser as a `webm` or `.mp4` file.

## What's supported?

✅ Quick export of BigBlueButton presentations containing audio, slides and whiteboard annotations<br  />

✅ Option to render the webcams and screen sharings (deskshare) in addition to the presentation<br  />

✅ Saving annotated slides as PNG so they can be merged into a new PDF<br  />  

## What's coming?

🔜 Integration into Greenlight's UI<br  />

🔜 Conversion of annotated slides into PDF using Cairo<br  />

🔜 Support of further interactive elements such as the cursor, chat, and polls<br  />

🔜 Speed improvements<br  />


## Usage
In your terminal, type

    ruby presentation-render.rb "URL_OF_YOUR_BBB-RECORDING"

### Required packages
librsvg
ffmpeg  version 4.4, ideally compiled with --enable-librsvg 
Ruby with Nokogiri, open-uri, cgi, and fileutils

## How it works

The script creates an SVG frame for every timestep in the recording and uses [FFmpeg's Concatenate](https://trac.ffmpeg.org/wiki/Slideshow) format to render the animation as a slideshow. This is achieved by exporting the SVG frames as intermediate PNG files using `librsvg`, which in turn allows the final annotated slides to be saved separately as well.

In contrast to other approaches, this script is **not** dependent on headless browsers, screen recorders, open source video editors... just plain Ruby to generate well-formed SVGs. Since the generated video has a variable frame rate, rendering happens blazing fast and results in small file sizes.

The end goal is to integrate this script in Greenlight's GUI with further options such as allowing the students and teachers to add webcams, screen recordings (deskshare), trim the file given start- and end times, download the annotated slides as a PDF with Cairo, choosing the desired resolution and so on.