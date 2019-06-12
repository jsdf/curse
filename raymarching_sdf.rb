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
Curses.init_pair(GRASS_PAIR, Curses::COLOR_WHITE, Curses::COLOR_GREEN)
Curses.init_pair(WATER_PAIR, Curses::COLOR_CYAN, Curses::COLOR_BLUE)
Curses.init_pair(MOUNTAIN_PAIR, Curses::COLOR_WHITE, Curses::COLOR_BLACK)
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

  def sub(v)
    Vec3.new(@x-v.x, @y-v.y, @z-v.z)
  end

  def mul(v)
    Vec3.new(@x*v.x, @y*v.y, @z*v.z)
  end

  def self.dot(a, b)
    a.x*b.x + a.y*b.y + a.z*b.z
  end

  def self.reflect(incident, normal)
    incident.sub(normal.mul_scalar(2.0 * self.dot(normal, incident)))
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


#
# Using the gradient of the SDF, estimate the normal on the surface at point p.
# 
def estimate_normal(
  p # vec3
)
  Vec3.new(
    scene_sdf(Vec3.new(p.x + $EPSILON, p.y, p.z)) - scene_sdf(Vec3.new(p.x - $EPSILON, p.y, p.z)),
    scene_sdf(Vec3.new(p.x, p.y + $EPSILON, p.z)) - scene_sdf(Vec3.new(p.x, p.y - $EPSILON, p.z)),
    scene_sdf(Vec3.new(p.x, p.y, p.z  + $EPSILON)) - scene_sdf(Vec3.new(p.x, p.y, p.z - $EPSILON))
  ).normalize
end


#
# Lighting contribution of a single point light source via Phong illumination.
# 
# The vec3 returned is the RGB color of the light's contribution.
#
# k_a: Ambient color
# k_d: Diffuse color
# k_s: Specular color
# alpha: Shininess coefficient
# p: position of point being lit
# eye: the position of the camera
# light_pos: the position of the light
# light_intensity: color/intensity of the light
#
# See https://en.wikipedia.org/wiki/Phong_reflection_model#Description
#
def phong_contrib_for_light(
 k_d, # vec3
 k_s, # vec3
 alpha, # float
 p, # vec3
 eye, # vec3
 light_pos, # vec3
 light_intensity # vec3
)
  n = estimate_normal(p) # vec3
  l = light_pos.sub(p).normalize # vec3
  v = eye.sub(p).normalize # vec3
  r = Vec3.reflect(l.mul_scalar(-1.0), n).normalize # vec3
  
  dot_l_n = Vec3.dot(l, n) # float
  dot_r_v = Vec3.dot(r, v) # float
  
  if dot_l_n < 0.0
    # Light not visible from this point on the surface
    return Vec3.new(0.0, 0.0, 0.0);
  end
  
  if dot_r_v < 0.0
    # Light reflection in opposite direction as viewer, apply only diffuse
    # component
    return light_intensity.mul(k_d.mul_scalar(dot_l_n))
  end
  return light_intensity.mul((k_d.mul_scalar(dot_l_n).add(k_s.mul_scalar(dot_r_v ** alpha))))
end



# 
# Lighting via Phong illumination.
# 
# The vec3 returned is the RGB color of that point after lighting is applied.
# k_a: Ambient color
# k_d: Diffuse color
# k_s: Specular color
# alpha: Shininess coefficient
# p: position of point being lit
# eye: the position of the camera
# 
# See https://en.wikipedia.org/wiki/Phong_reflection_model#Description
# 
def phong_illumination(
  k_a, # vec3
  k_d, # vec3
  k_s, # vec3
  alpha, # float
  p, # vec3
  eye, # vec3
  iTime # float
)
  ambient_light = Vec3.new(1.0, 1.0, 1.0).mul_scalar(0.5) # vec3 
  color = ambient_light.mul(k_a) # vec3 
  
  light1_pos = Vec3.new(4.0 * Math.sin(iTime), # vec3 
                        2.0,
                        4.0 * Math.cos(iTime))
  light1_intensity = Vec3.new(0.4, 0.4, 0.4) # vec3 
  
  color = color.add(phong_contrib_for_light(k_d, k_s, alpha, p, eye,
                                  light1_pos,
                                  light1_intensity))
  
  light2_pos = Vec3.new(2.0 * Math.sin(0.37 * iTime), # vec3 
                        2.0 * Math.cos(0.37 * iTime),
                        2.0)
  light2_intensity = Vec3.new(0.4, 0.4, 0.4) # vec3 
  
  color = color.add(phong_contrib_for_light(k_d, k_s, alpha, p, eye,
                                  light2_pos,
                                  light2_intensity))
  color
end

# these are two chars wide to account for console 'pixels' being tall
LIGHT_INTENSITY = [
  "  ", " .",
  "..", ".;",
  ";;", ";|",
  "||", "|*",
  "**", "00"
]

def main_image(
  screen_bounds, #vec2
  frag_coord, #vec2
  tick_count
)
  dir = ray_direction(45.0, screen_bounds, frag_coord) # vec3
  eye = Vec3.new(0.0, 0.0, 5.0)
  dist = shortest_distance_to_surface(eye, dir, $MIN_DIST, $MAX_DIST) # float
    
  if dist > $MAX_DIST - $EPSILON
    # Didn't hit anything
    return :transparent
  end
  
  # The closest point on the surface to the eyepoint along the view ray
  p = eye.add(dir.mul_scalar(dist)) # vec3
  
  k_a = Vec3.new(0.2, 0.2, 0.2); # vec3
  k_d = Vec3.new(0.7, 0.2, 0.2); # vec3
  k_s = Vec3.new(1.0, 1.0, 1.0); # vec3
  shininess = 10.0 # float
  
  color = phong_illumination(k_a, k_d, k_s, shininess, p, eye, tick_count); # vec3
  color = color.mul_scalar(1.5) # boost the brightness a bit

  luminance = [color.x+color.y+color.z/3.0, 0.9999].min

  LIGHT_INTENSITY[(luminance*10.0).floor]
end

$SCALE_X = 2.0
SOLID = "XX"
TRANSPARENT = "  "
screen = Vec2.new($max_x / $SCALE_X, $max_y)

tick_count = 0
loop do
  tick_count += 1

  # render screen  
  x_range = 0..screen.x
  y_range = 0..screen.y

  y_range.each do |y|
    x_range.each do |x|
      pixel = main_image(screen, Vec2.new(x, y), tick_count)
      color = pixel == :transparent ?  MOUNTAIN_PAIR : GRASS_PAIR
      pic = pixel == :transparent ? TRANSPARENT : pixel
      # puts "color #{color}"
      place_string(y, x * $SCALE_X, color, pic)
    end
  end

  # tick_count indicator
  place_string(screen.y-1, screen.x*$SCALE_X-1, MOUNTAIN_PAIR, (tick_count % 10).to_s)

  Curses.refresh
  sleep(0.1)
end


