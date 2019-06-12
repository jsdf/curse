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

# colors
GRASS_PAIR = 1
WATER_PAIR = 2
MOUNTAIN_PAIR = 3
FIRE_PAIR = 4
Curses.init_pair(GRASS_PAIR, Curses::COLOR_YELLOW, Curses::COLOR_GREEN)
Curses.init_pair(WATER_PAIR, Curses::COLOR_CYAN, Curses::COLOR_BLUE)
Curses.init_pair(MOUNTAIN_PAIR, Curses::COLOR_BLACK, Curses::COLOR_WHITE)
Curses.init_pair(FIRE_PAIR, Curses::COLOR_RED, Curses::COLOR_MAGENTA)

def place_string(y, x, color, string)
  Curses.attrset(Curses.color_pair(color))

  Curses.setpos(y, x)
  Curses.addstr(string)
end

DEFAULT_SIZE = 10

if ARGV.include? "small"
  $max_x = DEFAULT_SIZE * 2
  $max_y = DEFAULT_SIZE
else
  $max_x = Curses.cols == 0 ? DEFAULT_SIZE * 2 : Curses.cols
  $max_y = Curses.lines == 0 ? DEFAULT_SIZE : Curses.lines
end

# Raymarch SDF

$MAX_MARCHING_STEPS = 255
$MIN_DIST = 0.0
$MAX_DIST = 100.0
$EPSILON = 0.0001

class Vec2
  attr_accessor :x, :y

  def initialize(x, y)
    @x = x
    @y = y
  end

  def sub(v)
    Vec2.new(@x - v.x, @y - v.y)
  end

  def div_scalar(s)
    Vec2.new(@x/s, @y/s)
  end
end

class Vec3
  attr_accessor :x, :y, :z
  def initialize(x, y, z)
    @x = x
    @y = y
    @z = z
  end

  def length
    Math.sqrt(@x * @x + @y * @y + @z * @z)
  end

  def normalize
    l = length
    Vec3.new(@x/l, @y/l, @z/l)
  end

  def mul_scalar(s)
    Vec3.new(@x*s, @y*s, @z*s)
  end

  def add(v)
    Vec3.new(@x+v.x, @y+v.y, @z+v.z)
  end
end


# Signed distance function for a sphere centered at the origin with radius 1.0
def sphere_sdf(p) 
  p.length - 1.0
end

#
# Signed distance function describing the scene.
# 
# Absolute value of the return value indicates the distance to the surface.
# Sign indicates whether the point is inside or outside the surface,
# negative indicating inside.
def scene_sdf(sample_point)
  sphere_sdf(sample_point)
end

#
# Return the shortest distance from the eyepoint to the scene surface along
# the marching direction. If no part of the surface is found between start and end,
# return end.
# 
# eye: the eye point, acting as the origin of the ray
# marching_direction: the normalized direction to march in
# start_dist: the starting distance away from the eye
# end_dist: the max distance away from the ey to march before giving up
#
def shortest_distance_to_surface(
  eye, # vec3
  marching_direction, # vec3
  start_dist, # float
  end_dist # end
)
  depth = start_dist

  (0..$MAX_MARCHING_STEPS).each do |i|
    dist = scene_sdf(eye.add(marching_direction.mul_scalar(depth)))
    if dist < $EPSILON
      return depth
    end
    depth += dist
    if depth >= end_dist
      return end_dist
    end
  end
  return end_dist
end

def radians(angle)
  angle/180 * Math::PI
end


#
# Return the normalized direction to march in from the eye point for a single pixel.
# 
# field_of_view: vertical field of view in degrees
# size: resolution of the output image
# frag_coord: the x,y coordinate of the pixel in the output image
#
def ray_direction(
  field_of_view, # float
  size, # vec2
  frag_coord # vec2
)
  xy = frag_coord.sub(size.div_scalar(2.0)) # xy: vec2
  z = size.y / Math.tan(radians(field_of_view) / 2.0)
  return Vec3.new(xy.x, xy.y, -z).normalize
end


def main_image(
  screen_bounds, #vec2
  frag_coord #vec2
)
  dir = ray_direction(45.0, screen_bounds, frag_coord) # vec3
  eye = Vec3.new(0.0, 0.0, 5.0)
  dist = shortest_distance_to_surface(eye, dir, $MIN_DIST, $MAX_DIST) # float
  
  if dist > $MAX_DIST - $EPSILON
    # Didn't hit anything
    return :black
  end
  
  return :white
end

$SCALE_X = 2.0
SOLID = "XX"
TRANSPARENT = ".."
screen = Vec2.new($max_x / $SCALE_X, $max_y)

tick_count = 0
loop do
  tick_count += 1

  # render screen  
  x_range = 0..screen.x
  y_range = 0..screen.y

  y_range.each do |y|
    x_range.each do |x|
      pixel = main_image(screen, Vec2.new(x, y))
      color = pixel == :black ? MOUNTAIN_PAIR : GRASS_PAIR
      pic = pixel == :black ? TRANSPARENT : SOLID
      place_string(y, x * $SCALE_X, color, pic)
    end
  end

  # tick_count indicator
  place_string(screen.y-1, screen.x*$SCALE_X-1, MOUNTAIN_PAIR, (tick_count % 10).to_s)

  Curses.refresh
  sleep(0.1)
end


