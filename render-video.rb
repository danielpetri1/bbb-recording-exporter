# Render presentation
system("ffmpeg -f concat -i presentation-timestamps -c:v libvpx-vp9 -b:v 2500k -pix_fmt yuva420p -metadata:s:v:0 alpha_mode=\"1\" -vsync vfr -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' presentation.webm")

# Render whiteboard
system("ffmpeg -f concat -i whiteboard-timestamps -c:v libvpx-vp9 -b:v 2500k -pix_fmt yuva420p -metadata:s:v:0 alpha_mode=\"1\" -vsync vfr -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' whiteboard.webm")

# Presentation + Annotations + Deskshare + Webcams (.webm)
system("ffmpeg -i deskshare/deskshare.mp4 -c:v libvpx-vp9 -i presentation.webm -c:v libvpx-vp9 -i whiteboard.webm -i video/webcams.mp4 -filter_complex '[3]scale=w=iw/4:h=ih/4[cam];[0][1]overlay[tmp];[tmp][2]overlay[out];[out][cam]overlay=x=(main_w-overlay_w)' -b:v 2M -shortest -y presentation-deskshare-webcam.webm")

# Presentation + Annotations + Deskshare + Webcams (.mp4) - faster, patent encumbered
# system("ffmpeg -i deskshare/deskshare.mp4 -c:v libvpx-vp9 -i presentation.webm -c:v libvpx-vp9 -i whiteboard.webm -i video/webcams.mp4 -filter_complex '[3]scale=w=iw/4:h=ih/4[cam];[0][1]overlay[tmp];[tmp][2]overlay[out];[out][cam]overlay=x=(main_w-overlay_w)' -shortest -y presentation-deskshare-webcam.mp4")
