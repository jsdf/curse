#!/usr/bin/env ruby

require "curses"

$HEADLESS = ARGV.include? "headless"

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
unless $HEADLESS
  Curses.init_screen
  Curses.nl
  Curses.noecho
  Curses.curs_set 0
  Curses.start_color # enable color output
end

srand # seed random number generator

# colors
GRASS_PAIR = 1
WATER_PAIR = 2
MOUNTAIN_PAIR = 3
FIRE_PAIR = 4
unless $HEADLESS
  Curses.init_pair(GRASS_PAIR, Curses::COLOR_WHITE, Curses::COLOR_GREEN)
  Curses.init_pair(WATER_PAIR, Curses::COLOR_CYAN, Curses::COLOR_BLUE)
  Curses.init_pair(MOUNTAIN_PAIR, Curses::COLOR_WHITE, Curses::COLOR_BLACK)
  Curses.init_pair(FIRE_PAIR, Curses::COLOR_RED, Curses::COLOR_MAGENTA)
end

def place_string(y, x, color, string)
  unless $HEADLESS
    Curses.attrset(Curses.color_pair(color))

    Curses.setpos(y, x)
    Curses.addstr(string)
  end
end

DEFAULT_SIZE = 10

if ARGV.include? "small"
  $max_x = DEFAULT_SIZE * 2
  $max_y = DEFAULT_SIZE
else
  $max_x = Curses.cols == 0 ? DEFAULT_SIZE * 2 : Curses.cols
  $max_y = Curses.lines == 0 ? DEFAULT_SIZE : Curses.lines
end

$demo = :sphere
if ARGV.include? "box"
  $demo = :box
end

$demo_rotate = false
if ARGV.include? "rotate"
  $demo_rotate = true
end

$angled_view = $demo == :box
if ARGV.include? "side"
  $angled_view = false
end

$moving_lights = !($demo_rotate && $demo == :box)

def log(msg)
  # if $HEADLESS
  #   puts msg
  # else
    open('sdf.out', 'a') do |f|
      f.puts msg
    end
  # end
end

$global_memoize = {}
def memoize(key)
  if $global_memoize[key]
    return $global_memoize[key]
  else
    $global_memoize[key] = yield
  end
end


# Raymarch SDF
# based on the GLSL shader code from
# http://jamie-wong.com/2016/07/15/ray-marching-signed-distance-functions/

$MAX_MARCHING_STEPS = 255
$MIN_DIST = 0.0
$MAX_DIST = 100.0
$EPSILON = 0.0001
$tick_count = 0

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

  def self.cross(a, b)
    Vec3.new(
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x
    )
  end

  def self.reflect(incident, normal)
    incident.sub(normal.mul_scalar(2.0 * self.dot(normal, incident)))
  end

  def max_scalar(s)
    Vec3.new([@x,s].max, [@y,s].max, [@z,s].max)
  end

  def abs
    Vec3.new(@x.abs, @y.abs, @z.abs)
  end
end


def box_sdf(p, b)
  d = p.abs.sub(b) # vec3
  # length(max(d,0.0)) + min(max(d.x,max(d.y,d.z)),0.0); 
  d.max_scalar(0.0).length + [[d.x, [d.y, d.z].max].max, 0.0].min
end

# Signed distance function for a sphere centered at the origin with radius 1.0
def sphere_sdf(p) 
  p.length - 1.0
end


class Vec4
  attr_accessor :x,:y,:z,:w
  def initialize(x, y, z, w)
    @x = x
    @y = y
    @z = z
    @w = w
  end

  def xyz
    Vec3.new(x,y,z)
  end
end

# def rotate_y(
#   theta # float
# ) # mat4
#   c = cos(theta) # float
#   s = sin(theta) # float

#   return mat4(
#     vec4(c, 0, s, 0),
#     vec4(0, 1, 0, 0),
#     vec4(-s, 0, c, 0),
#     vec4(0, 0, 0, 1)
#   )
# end

class Mat3
  def initialize(col0, col1, col2)
    @m = [col0, col1, col2]
  end

  # https://stackoverflow.com/a/24594497
  def mul_vec3_right(v)
    Vec3.new(
      @m[0].x * v.x + @m[1].x * v.y + @m[2].x * v.z,
      @m[0].y * v.x + @m[1].y * v.y + @m[2].y * v.z,
      @m[0].z * v.x + @m[1].z * v.y + @m[2].z * v.z,
    )
  end
end

class Mat4
  def initialize(col0, col1, col2, col3)
    @m = [col0, col1, col2, col3]
  end

  # https://stackoverflow.com/a/24594497
  def mul_vec4_right(v)
    Vec4.new(
      @m[0].x * v.x + @m[1].x * v.y + @m[2].x * v.z + @m[3].x * v.w,
      @m[0].y * v.x + @m[1].y * v.y + @m[2].y * v.z + @m[3].y * v.w,
      @m[0].z * v.x + @m[1].z * v.y + @m[2].z * v.z + @m[3].z * v.w,
      @m[0].w * v.x + @m[1].w * v.y + @m[2].w * v.z + @m[3].w * v.w,
    )
  end
end

$rotation_memo = {}
#
# Rotation matrix around the Y axis.
#
def rotate_y(
  theta # float
) # mat3
  deg = degrees(theta).floor % 360
  if $rotation_memo[deg]
    return $rotation_memo[deg]
  end
  c = Math.cos(theta) # float
  s = Math.sin(theta) # float
  matrix = Mat3.new(
    Vec3.new(c, 0, s),
    Vec3.new(0, 1, 0),
    Vec3.new(-s, 0, c)
  );
  $rotation_memo[deg] = matrix
  matrix
end

#
# Signed distance function describing the scene.
# 
# Absolute value of the return value indicates the distance to the surface.
# Sign indicates whether the point is inside or outside the surface,
# negative indicating inside.
def scene_sdf(sample_point)
  zoom = $angled_view ? 1.0 : 0.5

  if $demo_rotate
    sample_point = rotate_y($fixed_tick_count / 30.0).mul_vec3_right(sample_point)
  end

  if $demo == :box
    box_sdf(sample_point, Vec3.new(zoom,zoom,zoom))
  else
    sphere_sdf(sample_point)
  end
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

def degrees(radians)
  radians * 180/Math::PI
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



#
# Return a transform matrix that will transform a ray from view space
# to world coordinates, given the eye point, the camera target, and an up vector.
#
# This assumes that the center of the camera is aligned with the negative z axis in
# view space when calculating the ray marching direction. See rayDirection.
# 
def view_matrix(
  eye, # vec3 
  center, # vec3 
  up # vec3 
) # mat4
  # Based on gluLookAt man page
  f = center.sub(eye).normalize # vec3
  s = Vec3.cross(f, up).normalize # vec3
  u = Vec3.cross(s, f) # vec3
  neg_f = f.mul_scalar(-1.0)
  Mat4.new(
    Vec4.new(s.x, s.y, s.z, 0.0),
    Vec4.new(u.x, u.y, u.z, 0.0),
    Vec4.new(neg_f.x, neg_f.y, neg_f.z, 0.0),
    Vec4.new(0.0, 0.0, 0.0, 1.0)
  );
end

# these are two chars wide to account for console 'pixels' being tall
LIGHT_RAMP_CHARS = [
  "  ", " .",
  "..", ".;",
  ";;", ";|",
  "||", "|*",
  "**", "00"
]

$eye = $angled_view ? Vec3.new(8.0, 5.0, 7.0) : Vec3.new(0.0, 0.0, 5.0)

def main_image(
  screen_bounds, #vec2
  frag_coord, #vec2
  tick_count
)
  world_dir = memoize("world_dir:#{frag_coord.x},#{frag_coord.y}") do
    if $angled_view
      view_dir = ray_direction(45.0, screen_bounds, frag_coord) # vec3
        
      view_to_world = view_matrix($eye, Vec3.new(0.0, 0.0, 0.0), Vec3.new(0.0, 1.0, 0.0)) # mat4

      (view_to_world.mul_vec4_right(Vec4.new(view_dir.x, view_dir.y, view_dir.z, 0.0))).xyz # vec3
    else
      ray_direction(45.0, screen_bounds, frag_coord) # vec3
    end
  end
    
  dist = shortest_distance_to_surface($eye, world_dir, $MIN_DIST, $MAX_DIST) # float
    
  if dist > $MAX_DIST - $EPSILON
    # Didn't hit anything
    return :transparent
  end
  
  # The closest point on the surface to the eyepoint along the view ray
  p = $eye.add(world_dir.mul_scalar(dist)) # vec3
  
  k_a = Vec3.new(0.2, 0.2, 0.2); # vec3
  k_d = Vec3.new(0.7, 0.2, 0.2); # vec3
  k_s = Vec3.new(1.0, 1.0, 1.0); # vec3
  shininess = 10.0 # float

  light_tick = $moving_lights ? tick_count / 10.0 : 0
  
  color = phong_illumination(k_a, k_d, k_s, shininess, p, $eye, light_tick); # vec3
  color = color.mul_scalar(1.5) # boost the brightness a bit

  luminance = [color.x+color.y+color.z/3.0, 0.9999].min
  light_intensity_scale = 10.0

  LIGHT_RAMP_CHARS[[(luminance*light_intensity_scale).floor,9].min]
end

$SCALE_X = 2.0
SOLID = "XX"
TRANSPARENT = "  "
screen = Vec2.new($max_x / $SCALE_X, $max_y)

FRAME_TIME = 1.0/60.0

$START_TIME = Time.new.to_f
$last_frame_time = Time.new.to_f
$fixed_tick_count = 0
$frame_timer_second = Time.new.to_i
$frame_timer_count = 0
$frame_timer_count_last = 0
loop do
  since_start = Time.new.to_f - $START_TIME
  $tick_count += 1
  $fixed_tick_count = (since_start / FRAME_TIME).to_i

  # render screen  
  x_range = 0..screen.x
  y_range = 0..screen.y

  y_range.each do |y|
    x_range.each do |x|
      pixel = main_image(screen, Vec2.new(x, y), $fixed_tick_count)
      color = pixel == :transparent ?  MOUNTAIN_PAIR : GRASS_PAIR
      pic = pixel == :transparent ? TRANSPARENT : pixel
      # puts "color #{color}"
      place_string(y, x * $SCALE_X, color, pic)
    end
  end

  # tick_count indicator
  place_string(screen.y-3, screen.x*$SCALE_X-2, MOUNTAIN_PAIR, ($tick_count % 60).to_s)
  place_string(screen.y-2, screen.x*$SCALE_X-2, MOUNTAIN_PAIR, ($fixed_tick_count % 60).to_s)
  # fps
  place_string(screen.y-1, screen.x*$SCALE_X-6, MOUNTAIN_PAIR, "fps=#{$frame_timer_count_last}")

  # place_string(screen.y-1, 0, MOUNTAIN_PAIR, "$rotation_memo=#{$rotation_memo.size}, #{$rotation_memo.to_a.last(4).to_h.keys}")

  Curses.refresh unless $HEADLESS

  # maintain framerate
  time = Time.new.to_f
  time_diff = time - $last_frame_time
  $last_frame_time = time
  log("frametime: #{time_diff*1000}")

  current_frame_timer_second = Time.new.to_i
  if current_frame_timer_second > $frame_timer_second
    $frame_timer_count_last = $frame_timer_count
    $frame_timer_count = 0
  else
    $frame_timer_count += 1
  end
  $frame_timer_second = current_frame_timer_second

  if time_diff < FRAME_TIME
    sleep(FRAME_TIME - time_diff)
  end
end


