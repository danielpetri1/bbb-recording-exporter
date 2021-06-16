# # Render slides + whiteboard + mouse + webcams + chat
# ffmpeg -f lavfi -i color=c=white:s=1920x1080 \
#  -f concat -safe 0 -i timestamps/whiteboard_timestamps \
#  -f concat -safe 0 -i timestamps/cursor_timestamps \
#  -f concat -safe 0 -i timestamps/chat_timestamps \
#  -i video/webcams.webm -filter_complex \
# '[4]scale=w=320:h=240[webcams];[0][1]overlay=x=320[slides];[slides][2]overlay=x=320[cursor];[cursor][3]overlay=y=240[chat];[chat][webcams]overlay' \
# -c:a aac -shortest -y merged.mp4

# # Render slides + whiteboard + mouse + webcams + deskshare
# ffmpeg -f lavfi -i color=c=white:s=1920x1080 \
#  -f concat -safe 0 -i timestamps/whiteboard_timestamps \
#  -f concat -safe 0 -i timestamps/cursor_timestamps \
#  -f concat -safe 0 -i timestamps/chat_timestamps \
#  -i video/webcams.webm \
#  -i deskshare/deskshare.webm -filter_complex \
# '[4]scale=w=320:h=240[webcams];[5]scale=w=1600:h=1080:force_original_aspect_ratio=1[deskshare];[0][deskshare]overlay=x=320[screenshare];[screenshare][1]overlay=x=320[whiteboard];[whiteboard][2]overlay=x=320[cursor];[cursor][3]overlay[chat];[chat][webcams]overlay' \
# -c:a aac -shortest -y merged.mp4


#### sendcmd tests

# No deskshare - mouse overlay method
ffmpeg -f lavfi -i color=c=white:s=1920x1080 \
    -f concat -safe 0 -i timestamps/whiteboard_timestamps \
    -framerate 10 -loop 1 -i cursor/cursor.svg \
    -framerate 1 -loop 1 -i chats/chat.svg \
    -i video/webcams.webm \
    -filter_complex "[2]sendcmd=f=timestamps/cursor_timestamps[cursor];[3]sendcmd=f=timestamps/chat_timestamps[chat];[4]scale=w=320:h=240[webcams];[0][1]overlay=x=320[slides];[slides][cursor]overlay@mouse[whiteboard];[whiteboard][chat]overlay@msg=y=1080[chats];[chats][webcams]overlay" \
    -c:a aac -shortest -y merged.mp4

# With deskshare
ffmpeg -f lavfi -i color=c=white:s=1920x1080 \
    -f concat -safe 0 -i timestamps/whiteboard_timestamps \
    -framerate 10 -loop 1 -i cursor/cursor.svg \
    -framerate 1 -loop 1 -i chats/chat.svg \
    -i video/webcams.webm \
    -i deskshare/deskshare.webm \
    -filter_complex "[2]sendcmd=f=timestamps/cursor_timestamps[cursor];[4]scale=w=320:h=240[webcams];[5]scale=w=1600:h=1080:force_original_aspect_ratio=1[deskshare];[0][deskshare]overlay=x=320:y=90[screenshare];[screenshare][1]overlay=x=320[slides];[slides][cursor]overlay@mouse[whiteboard];[whiteboard][3]overlay@msg=y=1080[chats];[chats][webcams]overlay" \
    -c:a aac -shortest -y merged.mp4


# Sendcmd chat test
ffmpeg -f lavfi -i color=c=white:s=1920x1080 \
    -framerate 1 -loop 1 -i chats/chat.svg \
    -filter_complex '[1]sendcmd=f=timestamps/chat_timestamps[chat];[0][chat]overlay@chat=y=1080' \
    -t 155 -y chat.mp4