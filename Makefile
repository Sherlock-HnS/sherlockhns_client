# Música do LMS (veja tools/add_music.sh)
#   make music URL=https://www.youtube.com/watch?v=...
#   make music-list
#   make music-verify
.PHONY: music music-list music-verify

music:
	@./tools/add_music.sh add "$(URL)"

music-list:
	@./tools/add_music.sh list

music-verify:
	@./tools/add_music.sh verify
