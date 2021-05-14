#!/bin/bash

# Render whiteboard
#ffmpeg -f concat -i whiteboard_timestamps -c:v libvpx-vp9 -b:v 2500k -pix_fmt yuva420p -metadata:s:v:0 alpha_mode=\"1\" -vsync vfr -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' whiteboard.webm

#system("ffmpeg -f concat -i whiteboard_timestamps -c:v libvpx-vp9 -b:v 2500k -pix_fmt yuva420p -metadata:s:v:0 alpha_mode=\"1\" -vsync vfr -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' whiteboard.webm")

# Presentation + Annotations + Deskshare + Webcams (.webm)
#system("ffmpeg -i deskshare/deskshare.mp4 -c:v libvpx-vp9 -i presentation.webm -c:v libvpx-vp9 -i whiteboard.webm -i video/webcams.mp4 -filter_complex '[3]scale=w=iw/4:h=ih/4[cam];[0][1]overlay[tmp];[tmp][2]overlay[out];[out][cam]overlay=x=(main_w-overlay_w)' -b:v 2500k -b:a 128k -shortest -y presentation-deskshare-webcam.webm")

# Presentation + Annotations + Deskshare + Webcams (.mp4) - faster, patent encumbered
# system("ffmpeg -i deskshare/deskshare.mp4 -c:v libvpx-vp9 -i presentation.webm -c:v libvpx-vp9 -i whiteboard.webm -i video/webcams.mp4 -filter_complex '[3]scale=w=iw/4:h=ih/4[cam];[0][1]overlay[tmp];[tmp][2]overlay[out];[out][cam]overlay=x=(main_w-overlay_w)' -shortest -y presentation-deskshare-webcam.mp4")

# Render Whiteboard + Annotations + Webcam
ffmpeg -f concat -i whiteboard_timestamps -i video/webcams.webm -pix_fmt yuv420p -lossless 1 -c:v libvpx-vp9 -b:v 2M -auto-alt-ref 0 -filter_complex '[0]scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white[whiteboard];[1]scale=w=iw/4:h=ih/4[cam];[whiteboard][cam]overlay' -acodec copy -shortest merged.webm

# Presentation: passes 1 and 2
ffmpeg -f concat -i presentation_timestamps -vsync vfr -pix_fmt yuva420p -c:v libvpx-vp9 -b:v 2M -pass 1 -metadata:s:v:0 alpha_mode="1" -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' -lossless 1 -an -f null /dev/null && \
ffmpeg -f concat -i presentation_timestamps -vsync vfr -pix_fmt yuva420p -c:v libvpx-vp9 -b:v 2M -pass 2 -metadata:s:v:0 alpha_mode="1" -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' -lossless 1 -an presentation.webm

# Whiteboard annotations: passes 1 and 2
ffmpeg -f concat -i whiteboard_timestamps -vsync vfr -pix_fmt yuva420p -c:v libvpx-vp9 -b:v 2M -pass 1  -metadata:s:v:0 alpha_mode="1" -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' -lossless 1 -an -f null /dev/null && \
ffmpeg -f concat -i whiteboard_timestamps -vsync vfr -pix_fmt yuva420p -c:v libvpx-vp9 -b:v 2M -pass 2  -metadata:s:v:0 alpha_mode="1" -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' -lossless 1 -an whiteboard.webm


# Whiteboard + Annotations (.mp4) - fast
ffmpeg -c:v libvpx-vp9 -i presentation.webm -c:v libvpx-vp9 -i whiteboard.webm -filter_complex '[0]fps=10,fifo[a];[1]fps=10,fifo[b];[a][b]overlay' -r 24 presentation_whiteboard.mp4

ffmpeg -f concat -i presentation_timestamps -f concat -i whiteboard_timestamps -filter_complex '[0]fps=10,fifo[a];[1]fps=10,fifo[b];[a][b]overlay' presentation_whiteboard.mp4

# Whiteboard + Annotations (.mp4) - fast
ffmpeg -f concat -i presentation_timestamps -f concat -i whiteboard_timestamps \
-filter_complex '[0]fps=24,scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white,fifo[a];[1]fps=24,scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white,fifo[b];[a][b]overlay' presentation_whiteboard.mp4

# Whiteboard + Annotations + .webm Webcam
ffmpeg -f concat -i presentation_timestamps -f concat -i whiteboard_timestamps -i video/webcams.mp4 \
-filter_complex '[0]fps=24,scale=w=1600:h=900:force_original_aspect_ratio=1,pad=1600:900:-1:-1:white,fifo[a];[1]fps=24,scale=w=1600:h=900:force_original_aspect_ratio=1,pad=1600:900:-1:-1:white,fifo[b];[2]scale=w=iw/4:h=ih/4[cam];[a][b]overlay[tmp];[tmp][cam]overlay=x=(main_w-overlay_w)' -shortest presentation_whiteboard_webcam.mp4


ffmpeg -f concat -i presentation_timestamps -vsync vfr -pix_fmt yuva420p -c:v libvpx-vp9 -b:v 2M -pass 1 -metadata:s:v:0 alpha_mode="1" -auto-alt-ref 0 -y -filter_complex 'scale=w=1600:h=900:force_original_aspect_ratio=1,pad=1600:900:-1:-1:white' -lossless 1 -an -f null /dev/null && \
ffmpeg -f concat -i presentation_timestamps -vsync vfr -pix_fmt yuva420p -c:v libvpx-vp9 -b:v 2M -pass 2 -metadata:s:v:0 alpha_mode="1" -auto-alt-ref 0 -y -filter_complex 'scale=w=1600:h=900:force_original_aspect_ratio=1,pad=1600:900:-1:-1:white' -lossless 1 -an presentation.webm

# Whiteboard annotations: passes 1 and 2
ffmpeg -f concat -i whiteboard_timestamps -vsync vfr -pix_fmt yuva420p -c:v libvpx-vp9 -b:v 2M -pass 1  -metadata:s:v:0 alpha_mode="1" -auto-alt-ref 0 -y -filter_complex 'scale=w=1600:h=900:force_original_aspect_ratio=1,pad=1600:900:-1:-1:white' -lossless 1 -an -f null /dev/null && \
ffmpeg -f concat -i whiteboard_timestamps -vsync vfr -pix_fmt yuva420p -c:v libvpx-vp9 -b:v 2M -pass 2  -metadata:s:v:0 alpha_mode="1" -auto-alt-ref 0 -y -filter_complex 'scale=w=1600:h=900:force_original_aspect_ratio=1,pad=1600:900:-1:-1:white' -lossless 1 -an whiteboard.webm


# Fast!

# Slide + Annotation
ffmpeg -c:v libvpx-vp9 -i presentation.webm -c:v libvpx-vp9 -i whiteboard.webm -filter_complex '[0]fps=24,fifo[a];[1]fps=24,fifo[b];[a][b]overlay' -shortest demo.mp4

# Slide + Annotation + Webcam
ffmpeg -c:v libvpx-vp9 -i presentation.webm -c:v libvpx-vp9 -i whiteboard.webm -i video/webcams.webm -filter_complex '[0]fps=24,fifo[a];[1]fps=24,fifo[b];[a][b]overlay[tmp];[2]scale=w=iw/4:h=ih/4[cam];[tmp][cam]overlay=x=(main_w-overlay_w)' -shortest lasttest.mp4