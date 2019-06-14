# curse
ruby curses demos

## setup

```bash
bundle install
```

## raymarching signed distance field renderer
```bash
bundle exec ruby raymarching_sdf.rb
# options
bundle exec ruby raymarching_sdf.rb small # render small view

bundle exec ruby raymarching_sdf_animated.rb # rotating box
bundle exec ruby raymarching_sdf_animated.rb torus # torus
```

## conway's game of life

```bash
bundle exec ruby life.rb # generate a random starting layout


# some examples, see https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life#Examples_of_patterns
bundle exec ruby life.rb glider # start with a 'glider'
bundle exec ruby life.rb blinker # start with a 'blinker'
bundle exec ruby life.rb block # start with a 'block'

```

## random
```bash
bundle exec ruby random.rb
```
