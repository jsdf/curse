#!/usr/bin/env ruby

# you can run this with some options:
# small - use small world
# block - init with just one block
# blinker - init with just one blinker
# glider - init with just one glider

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

# colors
GRASS_PAIR = 1
WATER_PAIR = 2
MOUNTAIN_PAIR = 3
FIRE_PAIR = 4
Curses.init_pair(GRASS_PAIR, Curses::COLOR_YELLOW, Curses::COLOR_GREEN)
Curses.init_pair(WATER_PAIR, Curses::COLOR_CYAN, Curses::COLOR_BLUE)
Curses.init_pair(MOUNTAIN_PAIR, Curses::COLOR_BLACK, Curses::COLOR_WHITE)
Curses.init_pair(FIRE_PAIR, Curses::COLOR_RED, Curses::COLOR_MAGENTA)

def place_string(x, y, color, string)
  Curses.attrset(Curses.color_pair(color))

  Curses.setpos(y, x)
  Curses.addstr(string)
end

# Game of Life

DEAD = 0
ALIVE = 1

DEFAULT_SIZE = 10

if ARGV.include? "small"
  $max_x = DEFAULT_SIZE * 2
  $max_y = DEFAULT_SIZE
else
  $max_x = Curses.cols == 0 ? DEFAULT_SIZE * 2 : Curses.cols
  $max_y = Curses.lines == 0 ? DEFAULT_SIZE : Curses.lines
end

class Grid
  attr_reader :width, :height

  def initialize(max_x, max_y)
    @width = max_x
    @height = max_y

    @x_range = 0...@width
    @y_range = 0...@height
    @grid = []
    @y_range.each do |y|
      @x_range.each do |x|
        @grid[y] = @grid[y] || []
        @grid[y][x] = DEAD
      end
    end
  end

  def copy_grid(from)
    @y_range.each do |y|
      @x_range.each do |x|
        @grid[y][x] = from[y][x]
      end
    end
  end

  def visit_neighbors(cell_x, cell_y)
    start_x = (cell_x - 1).clamp(0, @width - 1)
    start_y = (cell_y - 1).clamp(0, @height - 1)
    end_x = (cell_x + 1).clamp(0, @width - 1)
    end_y = (cell_y + 1).clamp(0, @height - 1)

    (start_y..end_y).each do |y|
      (start_x..end_x).each do |x|
        unless x == cell_x && y == cell_y
          yield @grid[y][x]
        end
      end
    end
  end

  def traverse
    @y_range.each do |y|
      @x_range.each do |x|
        yield x, y, @grid[y][x]
      end
    end
  end

  def neighbours_alive(cell_x, cell_y)
    alive_neighbors = 0
    visit_neighbors(cell_x, cell_y) do |neighbor|
      alive_neighbors += neighbor
    end
    alive_neighbors
  end

  def make_copy
    next_grid = Grid.new(width, height)
    next_grid.copy_grid(@grid)
    next_grid
  end

  def write(y, x, value)
    @grid[y][x] = value
  end

  # rules from https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life#Rules
  def tick
    next_grid = make_copy

    @y_range.each do |y|
      @x_range.each do |x|
        alive_neighbors = neighbours_alive(x, y)

        cell_state = @grid[y][x]
        start_state = cell_state
        if cell_state == ALIVE
          if alive_neighbors > 3 || alive_neighbors < 2
            cell_state = DEAD
          end
        else
          if alive_neighbors == 3
            cell_state = ALIVE
          end
        end

        next_grid.write(y, x, cell_state)
      end
    end
    next_grid
  end

  def init_random
    @y_range.each do |y|
      @x_range.each do |x|
        @grid[y][x] = rand(2) == 1 ? ALIVE : DEAD
      end
    end
  end

  # some examples from https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life#Examples_of_patterns
  def init_block
    # init 2x2 'block' starting state
    @grid[1][1] = ALIVE
    @grid[1][2] = ALIVE
    @grid[2][1] = ALIVE
    @grid[2][2] = ALIVE
  end

  def init_glider
    @grid[2][3] = ALIVE
    @grid[3][1] = ALIVE
    @grid[3][3] = ALIVE
    @grid[4][2] = ALIVE
    @grid[4][3] = ALIVE
  end

  def init_blinker
    @grid[2][1] = ALIVE
    @grid[2][2] = ALIVE
    @grid[2][3] = ALIVE
  end
end

# set up initial state of the world
$current_grid = Grid.new($max_x, $max_y)

if ARGV.include? "glider"
  $current_grid.init_glider
elsif ARGV.include? "block"
  $current_grid.init_block
elsif ARGV.include? "blinker"
  $current_grid.init_blinker
else
  $current_grid.init_random
end

tick_count = 0
loop do
  tick_count += 1

  # update world
  $current_grid = $current_grid.tick

  # render screen
  $current_grid.traverse do |x, y, cell_state|
    color = cell_state == DEAD ? MOUNTAIN_PAIR : GRASS_PAIR
    pic = cell_state == DEAD ? "." : "O"
    place_string(x, y, color, pic)
  end

  # tick_count indicator
  place_string($current_grid.width-1, $current_grid.height-1, MOUNTAIN_PAIR, (tick_count % 10).to_s)

  Curses.refresh
  sleep(0.1)
end