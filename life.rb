#!/usr/bin/env ruby

require "curses"

DEBUG = false

def debuglog(msg)
  if DEBUG
    puts msg
  end
end

def onsig(signal)
  # Curses.close_screen
  exit signal
end

%w[HUP INT QUIT TERM].each do |sig|
  unless trap(sig, "IGNORE") == "IGNORE"  # previous handler
    trap(sig) {|s| onsig(s) }
  end
end

unless DEBUG
  # curses setup stuff
  Curses.init_screen
  Curses.nl
  Curses.noecho
  Curses.curs_set 0
  Curses.start_color # enable color output
end

srand # seed random number generator

GRASS_PAIR = 1
WATER_PAIR = 2
MOUNTAIN_PAIR = 3
FIRE_PAIR = 4

unless DEBUG
  Curses.init_pair(GRASS_PAIR, Curses::COLOR_YELLOW, Curses::COLOR_GREEN)
  Curses.init_pair(WATER_PAIR, Curses::COLOR_CYAN, Curses::COLOR_BLUE)
  Curses.init_pair(MOUNTAIN_PAIR, Curses::COLOR_BLACK, Curses::COLOR_WHITE)
  Curses.init_pair(FIRE_PAIR, Curses::COLOR_RED, Curses::COLOR_MAGENTA)
end

def place_string(x, y, color, string)
  unless DEBUG
    Curses.attrset(Curses.color_pair(color))

    Curses.setpos(y, x)
    Curses.addstr(string)
  end
end

# Game of Life

DEAD = 0
ALIVE = 1

SIZE = 10

if ARGV.include? "small"
  @max_x = SIZE * 2
  @max_y = SIZE
else
  @max_x = Curses.cols == 0 ? SIZE * 2 : Curses.cols
  @max_y = Curses.lines == 0 ? SIZE : Curses.lines
end


# world
@x_range = 0...@max_x
@y_range = 0...@max_y

def make_grid
  grid = []
  @y_range.each do |y|
    @x_range.each do |x|
      grid[y] = grid[y] || []
      grid[y][x] = DEAD
    end
  end
  return grid
end

def copy_grid(from, to)
  @y_range.each do |y|
    @x_range.each do |x|
      to[y][x] = from[y][x]
    end
  end
end

# init grid
@grid = make_grid


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

def init_random
  @y_range.each do |y|
    @x_range.each do |x|
      @grid[y][x] = rand(2) == 1 ? ALIVE : DEAD
    end
  end
end

if ARGV.include? "glider"
  init_glider
elsif ARGV.include? "block"
  init_block
elsif ARGV.include? "blinker"
  init_blinker
else
  init_random
end
    

def visit_neighbors(cell_x, cell_y)
  start_x = (cell_x - 1).clamp(0, @max_x - 1)
  start_y = (cell_y - 1).clamp(0, @max_y - 1)
  end_x = (cell_x + 1).clamp(0, @max_x - 1)
  end_y = (cell_y + 1).clamp(0, @max_y - 1)

  debuglog "visit_neighbors #{cell_x} #{cell_y}, start_x=#{start_x} start_y=#{start_y} end_x=#{end_x} end_y=#{end_y}"

  (start_y..end_y).each do |y|
    (start_x..end_x).each do |x|
      debuglog "neighbor #{x} #{y}"
      unless x == cell_x && y == cell_y
        debuglog "visit #{@grid[y][x]}"
        yield @grid[y][x]
      end
    end
  end
end

# rules from https://natureofcode.com/book/chapter-7-cellular-automata/#76-the-game-of-life
def update_grid
  next_grid = make_grid
  copy_grid(@grid, next_grid)

  @y_range.each do |y|
    @x_range.each do |x|
      alive_neighbors = 0
      visit_neighbors(x, y) do |neighbor|
        alive_neighbors += neighbor
      end

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
      next_grid[y][x] = cell_state

      debuglog "#{x}, #{y} alive_neighbors=#{alive_neighbors} from=#{start_state} to=#{cell_state}"
    end
  end
  @grid = next_grid
end

tick = 0
loop do
  tick += 1

  # update world
  update_grid
  exit if DEBUG

  # render screen
  @y_range.each do |y|
    @x_range.each do |x|
      cell_state = @grid[y][x]
      color = cell_state == DEAD ? MOUNTAIN_PAIR : GRASS_PAIR
      pic = cell_state == DEAD ? "." : "O"
      place_string(x, y, color, pic)
    end
  end

  # tick indicator
  place_string(@max_x-1, @max_y-1, MOUNTAIN_PAIR, (tick % 10).to_s)

  Curses.refresh unless DEBUG
  sleep(0.1)
end