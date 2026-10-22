extends Node

var music: StrudelPlayer

func _ready() -> void:
	music = StrudelPlayer.new()
	add_child(music)

	music.play("""

const intensity = 0.5625

setcpm(130/4)

// Acid melody
$: n("<0 4 0 9 7>*16")
  .scale("G:minor")
  .transpose("<-12!2 -14!1 -16!1 -10!2>")
  .orbit(3)
  .s("sawtooth")
  .lpf(100)
  .lpenv(intensity * 9)
  .lps(0.2)
  .lpd(0.12)
  .lpq(2)
  .decay(0.16)
  .sustain(0)
  .release(0.05)
  .gain(0.7)

$: s("gm_taiko_drum:2!4")
  .gain(intensity)
  .duck("3:4:5:6")
  .duckdepth(0.8)
  .duckatt(.16)

	""")
