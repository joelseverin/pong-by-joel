pong.smc: pong.asm pong.link tiles.bin
	wla-65816 -vo pong.asm pong.obj
	wlalink -vr pong.link pong.smc

tiles.bin: mktiles.php
	./mktiles.php
