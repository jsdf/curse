#!/usr/bin/env ruby

require "curses"


def onsig(signal)
  Curses.close_screen
  exit signal
end

%w[HUP INT QUIT TERM].each do |sig|
  unless trap(sig, "IGNORE") == "IGNORE"  # previous handler
    trap(sig) {|s| onsig(s) }
  end
end

# curses setup stuff
Curses.init_screen
Curses.nl
Curses.noecho
Curses.curs_set 0
Curses.start_color # enable color output
srand # seed random number generator

GRASS_PAIR = 1
WATER_PAIR = 2
MOUNTAIN_PAIR = 3
FIRE_PAIR = 4

Curses.init_pair(GRASS_PAIR, Curses::COLOR_YELLOW, Curses::COLOR_GREEN)
Curses.init_pair(WATER_PAIR, Curses::COLOR_CYAN, Curses::COLOR_BLUE)
Curses.init_pair(MOUNTAIN_PAIR, Curses::COLOR_BLACK, Curses::COLOR_WHITE)
Curses.init_pair(FIRE_PAIR, Curses::COLOR_RED, Curses::COLOR_MAGENTA)
 
x_range = 0...Curses.cols
y_range = 0...Curses.lines
alphabet = ("a".."z").to_a

def place_string(x, y, color, string)
  Curses.attrset(Curses.color_pair(color))

  Curses.setpos(y, x)
  Curses.addstr(string)
end
 
loop do
  # render screen
  x_range.each do |x|
    y_range.each do |y|
      place_string x, y, rand(0...4), alphabet[rand(alphabet.length)]
    end
  end

  Curses.refresh
  sleep(0.1)
end