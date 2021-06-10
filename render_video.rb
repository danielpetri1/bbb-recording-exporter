# Render slides + whiteboard + mouse + webcams + chat
ffmpeg -f lavfi -i color=c=white:s=1920x1080 \
 -f concat -safe 0 -i timestamps/whiteboard_timestamps \
 -f concat -safe 0 -i timestamps/cursor_timestamps \
 -f concat -safe 0 -i timestamps/chat_timestamps \
 -i video/webcams.webm -filter_complex \
'[4]scale=w=320:h=240[webcams];[0][1]overlay=x=320[slides];[slides][2]overlay=x=320[cursor];[cursor][3]overlay=y=240[chat];[chat][webcams]overlay' \
-c:a aac -shortest -y merged.mp4

# Render slides + whiteboard + mouse + webcams + deskshare
ffmpeg -f lavfi -i color=c=white:s=1920x1080 \
 -f concat -safe 0 -i timestamps/whiteboard_timestamps \
 -f concat -safe 0 -i timestamps/cursor_timestamps \
 -f concat -safe 0 -i timestamps/chat_timestamps \
 -i video/webcams.webm \
 -i deskshare/deskshare.webm -filter_complex \
'[4]scale=w=320:h=240[webcams];[5]scale=w=1600:h=1080:force_original_aspect_ratio=1[deskshare];[0][deskshare]overlay=x=320[screenshare];[screenshare][1]overlay=x=320[whiteboard];[whiteboard][2]overlay=x=320[cursor];[cursor][3]overlay[chat];[chat][webcams]overlay' \
-c:a aac -shortest -y merged.mp4


#### sendcmd tests
ffmpeg -f lavfi -i color=c=white:s=1600x1080 -t 973 -vf "sendcmd=f=timestamps/cursor_timestamps,drawtext=fontsize=20:fontcolor=red:text=•:fontfile=/System/Library/Fonts/Supplemental/Verdana.ttf" -y out.mp4

ffmpeg -f lavfi -i color=c=white:s=1600x1080 \
 -f concat -safe 0 -i timestamps/whiteboard_timestamps \
 -filter_complex '[0][1]overlay[slides];[slides]sendcmd=f=timestamps/cursor_timestamps,drawtext=fontsize=30:fontcolor=red:text=•:fontfile=/System/Library/Fonts/Supplemental/Verdana.ttf' \
-c:a aac -shortest -y -t 300 merged.mp4