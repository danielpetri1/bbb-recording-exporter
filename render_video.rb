# Create white solid background (limits recordings to 12 hours)
# ffmpeg -f lavfi -i color=c=white:s=1920x1080 -loop 1 -t 43200 -video_track_timescale 90k bg.mp4

# Render slides + whiteboard + mouse + webcams
ffmpeg  -i bg.mp4 \
 -f concat -safe 0 -i timestamps/whiteboard_timestamps \
 -f concat -safe 0 -i timestamps/cursor_timestamps \
 -i video/webcams.webm -filter_complex \
'[1]scale=w=1600:h=900:force_original_aspect_ratio=1,fifo[a];[2]scale=w=1600:h=900:force_original_aspect_ratio=1,fifo[b];[3]scale=w=320:h=240[c];[0][a]overlay=x=320[tmp];[tmp][b]overlay=x=320[tmp2];[tmp2][c]overlay' \
-c:a aac -shortest -y merged.mp4


ffmpeg -f lavfi -i color=c=white:s=1920x1080 \
 -f concat -safe 0 -i timestamps/whiteboard_timestamps \
 -f concat -safe 0 -i timestamps/cursor_timestamps \
 -i video/webcams.webm -filter_complex \
'[1]scale=w=1600:h=900:force_original_aspect_ratio=1,fifo[a];[2]scale=w=1600:h=900:force_original_aspect_ratio=1,fifo[b];[3]scale=w=320:h=240[c];[0][a]overlay=x=320[tmp];[tmp][b]overlay=x=320[tmp2];[tmp2][c]overlay' \
-c:a aac -shortest -y merged.mp4

# Render slides + whiteboard + mouse + webcams + deskshare
ffmpeg -f lavfi -i color=c=white:s=1920x1080 \
 -f concat -safe 0 -i timestamps/whiteboard_timestamps \
 -f concat -safe 0 -i timestamps/cursor_timestamps \
 -i video/webcams.webm \
 -i deskshare/deskshare.webm -filter_complex
'[1]scale=w=1600:h=900:force_original_aspect_ratio=1,fifo[a];[2]scale=w=1600:h=900:force_original_aspect_ratio=1,fifo[b];[3]scale=w=320:h=240[c];[0][4]overlay=x=480:y=90[tmp];[tmp][a]overlay=x=320[tmp2];[tmp2][b]overlay=x=320[tmp3];[tmp3][c]overlay' \
-c:a aac -shortest -y merged.mp4