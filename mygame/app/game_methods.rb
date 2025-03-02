module GameMethods
  def nokia
    outputs[:nokia]
  end

  def outputs
    @args.outputs
  end

  def inputs
    @args.inputs
  end

  def audio
    @args.audio
  end

  def state
    @args.state
  end

  def geometry
    @args.geometry
  end

  def tick_setup
    set_defaults
    # GTK.write_file HIGH_SCORE_FILE_PATH, "0"
    state.high_score = (GTK.read_file(HIGH_SCORE_FILE_PATH)).to_i
    state.next_scene = :title
  end

  def tick_title
    state.next_scene = :play
  end

  def tick_over
    calc_cloud
    calc_crows
    calc_bombs
    calc_pitchforks
    calc_hit_crows
    calc_explosions
    render_score
    render_cloud
    render_bombs
    render_crows
    render_pitchforks
    render_explosions
    render_held_pitchfork_dots
    if state.total_score > state.high_score
      state.high_score = state.total_score
      GTK.write_file HIGH_SCORE_FILE_PATH, "#{state.high_score}"
    end
    render_high_score
  end

  def start_a_new_game?
    GTK.reset_next_tick if inputs.keyboard.key_down.r
  end

  def scene_ticker
    current_scene = state.current_scene
    case current_scene
    when :setup
      tick_setup
    when :title
      tick_title
    when :play
      tick_play
      render_fps
    when :over
      tick_over
    end

    unless state.game_paused
      state.clock += 1
      state.wave_counter += 1
    end

    if state.current_scene != current_scene
      raise "Scene was changed incorrectly. Set args.state.next_scene to change scenes."
    end

    if state.next_scene
      state.current_scene = state.next_scene
      state.next_scene = nil
    end
  end

  def check_thrown_pitchfork_input
    return if state.player.alive == false
    # check whether to throw a pitchfork
    if state.player.held.any? && (inputs.keyboard.key_down.space || inputs.keyboard.key_down.w || inputs.keyboard.key_down.kp_eight)
      oldest_powerup = state.player.held.shift
      oldest_powerup[:held] = false
      oldest_powerup[:y] = 4
      oldest_powerup[:x] = state.player.x + 5
      oldest_powerup[:respawn_timer] = state.clock + 100
    end
  end

  def check_move_player_input
    # process the movement of the player on even frames
    return if !state.clock.zmod?(2) || state.player.alive == false

    state.player.anim = :idle if state.player.anim == :move
    if (inputs.keyboard.left || inputs.keyboard.kp_four) && state.player.x > 0
      state.player.x -= 1
      state.player.flip = true
      state.player.anim = :move
      state.player.shield = false
    elsif (inputs.keyboard.right || inputs.keyboard.kp_six) && state.player.x < 72
        state.player.x += 1
        state.player.flip = false
        state.player.anim = :move
        state.player.shield = false
    end
  end

  def calc_shield
    state.player.shield = false if state.player.shield_at.elapsed_time(state.clock) > 600
    return if state.player.shield == false

    state.crow_rects.each do |crow|
      # also unlucky if a crow hits a shield
      if geometry.intersect_rect?(shield_rect, crow) && state.player.shield == true
        # just incase - don't add this crow if it is already there
        state.hit_crows << { crow: crow } unless state.hit_crows.any? { |entry| entry[:crow] == crow }
      end
    end
  end

  def calc_cloud
    state.cloud_x -= 0.03
    state.cloud_x = 84 if state.cloud_x < -17
  end

  def calc_pitchforks
    fork_rain = state.cloud_pitchforks
    cloud_x = state.cloud_x.to_i
    state.pitchforks.each do |p|
      # pitchfork respawn
      if p[:respawn_timer] && state.clock >= p[:respawn_timer]
        p[:respawn_timer] = nil
        p[:x] = p[:ox]
        p[:y] = 0
        # move pitchforks
      elsif p[:y] != 0
        p[:y] += 1 if p[:y] > 1
        state.score_multiplier = 1 if p.y > 50
      end

      next if p[:held] || p[:y] != 0
      # collect a pitchfork
      if state.player.x < p[:x] + 3 && state.player.x + 12 > p[:x] && state.player.alive == true
          state.player.held << p
          p[:held] = true
      end
    end
    # check pitchfork collision
    state.pitchforks.each do |pitchfork|
      half_size = (state.crow_rects.size.to_f / 2).ceil
      crows_to_process = state.clock.even? ? state.crow_rects.first(half_size) : state.crow_rects.last(state.crow_rects.size - half_size)
      crows_to_process.each do |crow|
        crow_id = crow.id
        # avoid processing any already hit crows
        next if state.hit_crows.any? { |c| c.crow.id == crow_id }

        if geometry.intersect_rect?(pitchfork, crow)
          state.hit_crows << { crow: crow }
          pitchfork.y = -10
          state.total_score += 10 * state.score_multiplier
          # caps the max per crow at 500 points
          state.score_multiplier = [state.score_multiplier * 2, 50].min
          if state.score > state.extra_life
            state.player.lives += 1 if state.player.lives < 6
            state.extra_life *= 2
          end
          # surely this isn't necessary :)
          state.score = 999999999 if state.score > 999999999
          # chance for a crow to drop a powerup
        end

        # crow hit by rain ?
        if geometry.intersect_rect?(fork_rain[0], crow)
          state.hit_crows << { crow: crow }
        end
        if geometry.intersect_rect?(fork_rain[1], crow)
          state.hit_crows << { crow: crow }
        end
        if geometry.intersect_rect?(fork_rain[2], crow)
          state.hit_crows << { crow: crow }
        end
        if geometry.intersect_rect?(fork_rain[3], crow)
          state.hit_crows << { crow: crow }
        end
        if geometry.intersect_rect?(fork_rain[4], crow)
          state.hit_crows << { crow: crow }
        end
      end

      # check if you have hit the cloud
      if state.cloud_x <= 68 && state.cloud_x >= 0
        if geometry.intersect_rect?(pitchfork, state.cloud_rect) && !state.raining
          state.cloud_hit_time ||= state.clock
          state.cloud_hits += 1
          pitchfork.y = -10
          audio[:cloud] ||= {
            input: 'sounds/hit.ogg',          # Filename
            x: 0.0, y: 0.0, z: 0.0,           # Relative position to the listener, x, y, z from -1.0 to 1.0
            gain: 1.0,                        # Volume (0.0 to 1.0)
            pitch: 1.0,                       # Pitch of the sound (1.0 = original pitch)
            paused: false,                    # Set to true to pause the sound at the current playback position
            looping: false,                   # Set to true to loop the sound/music until you stop it
          }
        end
      end
    end
    state.raining = true if state.cloud_hits >= 5

    if state.cloud_hit_time && state.cloud_hit_time.elapsed_time(state.clock) > 180
      state.cloud_hit_time = nil
      state.cloud_hits = 0
    end

    # quickly count up to the total score
    if state.score + 10 < state.total_score
      state.score += 10
    elsif state.score + 1 <= state.total_score
      state.score += 1
    end
  end

  def pitchfork_rain
    sprites_to_render = []
    # move and render existing cloud rain
    state.cloud_pitchforks.each do |fork|
      next if fork.y == -10

      sprites_to_render << {
        x: fork.x,
        y: fork.y,
        w: 3,
        h: 6,
        path: "sprites/pitchfork.png",
        flip_vertically: true
      }

      if state.clock.zmod? 2
        fork.y -= 1 unless state.game_paused
        fork.y = -10 if fork.y < -10
      end
    end

    nokia.sprites << sprites_to_render

    # do not start a falling pitchfork unless all the pitchforks are below this y coordinate
    return unless state.cloud_pitchforks.all? { |p| p[:y] < 25 }

    state.raining = false if state.cloud_x > 68 || state.cloud_x < 0
    return unless state.raining

    pf = [0, 1, 2, 3, 4].sample
    if state.cloud_pitchforks[pf].y == -10
      state.cloud_pitchforks[pf].y = state.cloud_y - 3
      state.cloud_pitchforks[pf].x = (state.cloud_x.to_i + (pf * 3) + 1)
    end

    # is the player caught in the rain without a hat ?
    return if state.player.shield == true || state.player.alive == false
    return if state.hat.hat_state == :worn && state.hat.hat_stolen == false

    state.cloud_pitchforks.each do |fork|
      next if fork.y == -10

      if geometry.intersect_rect?(fork, state.head_rect)
        crow_hit_sound
        state.explosions.concat(create_explosion(fork.x + 1, fork.y))
        state.player.alive = false
        state.player.lives -= 1
        if state.player.y == 0
          audio[:lost] ||= {
            input: 'sounds/lost.ogg',
            x: 0.0, y: 0.0, z: 0.0,
            gain: 1.0,
            pitch: 1.0,
            paused: false,
            looping: false,
          }
        end
      end
    end
  end

  def calc_hit_crows
    return if state.hit_crows.empty?

    state.hit_crows.each do |hit|
      crow_hit_sound
      state.explosions.concat(create_explosion(hit[:crow][:x] + 4, hit[:crow][:y] + 1))
    end

    removed_crow_ids = state.hit_crows.map { |hit| hit[:crow][:id] }

    # Set hat false if one of these has it
    crow_to_update = state.active_crows.find { |c| removed_crow_ids.include?(c[:id]) && c[:hat] == true }
    if crow_to_update
      state.total_score += 1000 unless state.game_over == true
      crow_to_update[:hat] = false
      state.hat.hat_stolen = false
      state.hat.hat_state = :fall
      state.hat.x = crow_to_update.x + (crow_to_update.flip == true ? -3 : 3)
      state.hat.y = crow_to_update.y - 6
    end

    state.active_crows.reject! { |crow| removed_crow_ids.include?(crow[:id]) }
    state.hit_crows.reject! { |hit| removed_crow_ids.include?(hit[:crow][:id]) }
    if state.active_crows.empty? && !state.game_over
      state.bomb_chance = 0.001
      state.new_wave = true
      state.wave_counter = 1
      state.total_score += 1000
    end
  end

  def crow_hit_sound
    audio[rand] ||= {
      input: 'sounds/hit.ogg',
      x: 0.0, y: 0.0, z: 0.0,
      gain: 1.0,
      pitch: 1.0,
      paused: false,
      looping: false,
    }
  end

  def create_explosion(x, y, num_particles = 100, speed = 0.4)
    num_particles.times.map do
      angle = rand * Math::PI * 2
      velocity = rand * speed * 2
      {
        x: x,
        y: y,
        w: 1,
        h: 1,
        path: :pixel,
        r: 0x43,
        g: 0x52,
        b: 0x3d,
        dx: Math.cos(angle) * velocity,
        dy: Math.sin(angle) * velocity,
        lifetime: 20 + rand(10),
        damping: 0.9 + rand * 0.05
      }
    end
  end

  def calc_explosions
    # Update explosion particles each frame
    state.explosions.each do |particle|
      particle[:x] += particle[:dx]
      particle[:y] += particle[:dy]
      particle[:lifetime] -= 1
      # Apply damping to gradually slow movement
      particle[:dx] *= particle[:damping]
      particle[:dy] *= particle[:damping]
    end

    # Remove expired particles
    state.explosions.reject! { |particle| particle[:lifetime] <= 0 }
  end

  def calc_wave
    return unless state.new_wave

    case state.wave
    when 6
      state.wave = 10
      # state.bomb_chance *= 1.1
    when 16
      state.wave = 20
      # state.bomb_chance *= 1.1
    end

    state.crows_wave_max = state.wave * 2
    state.crows_wave_max = [state.crows_wave_max, 50].min
    state.active_crows = state.crows.first(state.crows_wave_max)
    state.active_crows.each do |crow|
      set_state(entity: crow, state: :spawn)
    end

    # logic for game over, maybe some maximum amount of waves to survive
    state.wave += 1
    state.new_wave = false
  end

  def calc_drop_bomb
    return if state.active_crows.empty?

    state.active_crows.each do |crow|
      # skip crows that are spawning
      next if crow.state != :move
      # crow shouldn't be too far left or right when bombing
      if crow.x > 0 && crow.x < 75
        if rand < state.bomb_chance
          state.bombs << { id: crow.id, x: crow.x + 4, y: crow.y - 10, exploded: false }
          # only one crow can drop a bomb in a given frame
          return
        end
      end
    end
  end

  def calc_bombs
    if state.wave_counter.zmod? 3600
      state.bomb_chance *= 2
      state.wave_counter = 1
    end

    calc_drop_bomb
    return if state.bombs.empty?

    state.bombs.each do |bomb|
      bomb.y -= 0.1

      bomb_rect = { x: bomb.x, y: bomb.y, w: 3, h: 3}
      shield_hit = state.player.shield == true && geometry.intersect_rect?(bomb_rect, shield_rect)
      # bomb has hit the shield, or the bottom of the screen
      if bomb.y < 0 || shield_hit
        bomb.exploded = true
        audio[rand] ||= {
          input: 'sounds/hit.ogg',
          x: 0.0, y: 0.0, z: 0.0,
          gain: 1.0,
          pitch: 1.0,
          paused: false,
          looping: false,
        }
        state.explosions.concat(create_explosion(bomb.x, bomb.y))
        player_l = state.player.x - 4
        player_r = state.player.x + 13
        if bomb.x > player_l && bomb.x < player_r && state.game_over == false && state.player.shield == false && state.player.alive == true
          state.player.alive = false
          state.player.lives -= 1
          if state.player.y == 0
            audio[:lost] ||= {
              input: 'sounds/lost.ogg',
              x: 0.0, y: 0.0, z: 0.0,
              gain: 1.0,
              pitch: 1.0,
              paused: false,
              looping: false,
            }
          end
        end
      end
    end
    state.bombs.reject! { |bomb| bomb[:exploded] == true }
  end

  def calc_crows
    return if state.new_wave

    update_crows
  end

  def create_crow(
    id: 0,
    x: 0,
    y: 0,
    w: 10,
    h: 0,
    dx: 0,
    dy: 0,
    xv: 0,
    yv: 0,
    xa: 0,
    ya: 0,
    flip: false,
    hat: false,
    offset: Numeric.rand(0..12),
    flap_speed: [3, 4, 5].sample,
    frame: 0,
    state: :idle,
    state_timer: 0,
    attack_delay: 0,
    sprite_index: 0
  )
    {
      id: id,
      x: x,
      y: y,
      w: w,
      h: h,
      dx: dx,
      dy: dy,
      xv: xv,
      yv: yv,
      xa: xa,
      ya: ya,
      flip: flip,
      hat: hat,
      offset: offset,
      flap_speed: flap_speed,
      frame: frame,
      state: state,
      state_timer: state_timer,
      attack_delay: attack_delay,
      sprite_index: sprite_index
    }
  end

  def update_crows
    crow_rects = []
    state.active_crows.each do |crow|
      # determine crow frame/size for collision and render uses
      sprite_index = 0.frame_index 13, crow[:flap_speed], true, state.clock
      sprite_index = (sprite_index + crow[:offset]) % 13
      crow.h = state.crow_frames[sprite_index][:h]
      crow.sprite_index = sprite_index

      case crow.state
      when :spawn
        crow_spawn crow
      when :move
        crow_move crow
        crow_rects << { x: crow.x + 1, y: crow.y - crow.h + 1, w: 8, h: crow.h - 6, id: crow.id}
      end
    end
    state.crow_rects = crow_rects
    # sometimes check if a crow steals the hat
    return unless state.clock.zmod? 3
    # We fall through to here 1 out of every 3 frames
    return if state.hat.hat_stolen

    state.active_crows.each do |crow|
      crow_rect = { x: crow.x + 1, y: crow.y - crow.h + 1, w: 8, h: crow.h - 6 }
      if geometry.intersect_rect?(state.hat.hat_rect, crow_rect) && state.player.alive == true && state.hat.hat_state == :worn
        state.hat.hat_stolen = true
        crow.hat = true
        return
      end
    end
  end

  def crow_spawn crow
    update_crow_y crow

    # if the crow has fully spawned
    if crow.y < 50
      set_state(entity: crow, state: :move)
      # check where the crow is onscreen, set facing and initial velocity
      crow.xv = Numeric.rand(0.05..1)
      crow.yv = Numeric.rand(0.05..0.2) * -1
      set_crow_facing crow
    end
  end

  def set_crow_facing crow
    if crow.x >= 48
      crow.xv *= -1
      crow.flip = true
    else
      crow.flip = false
    end
  end

  def crow_move crow
    update_crow_x crow
    update_crow_y crow
  end

  def update_crow_x crow
    crow.dx = crow.dx + crow.xv
    if crow.dx >= 1
      crow.dx = 0
      crow.x += 1
      # has the crow flown too far right ?
      crow.x = -11 if crow.x > 95
    elsif crow.dx <= -1
      crow.dx = 0
      crow.x -= 1
      # has the crow flown too far left ?
      crow.x = 85 if crow.x < -20
    end
    chance_to_change_dir_x crow
  end

  def update_crow_y crow
    crow.dy = crow.dy + crow.yv
    if crow.dy >= 1
      crow.dy = 0
      crow.y += 1
    elsif crow.dy <= -1
      crow.dy = 0
      crow.y -= 1
    end
    # if crow is heading down and too far down, go up
    if crow.y < 26 && crow.yv < 0
      crow.yv *= -1
    end
    # if crow is heading up and too far up, go down
    if crow.y > 52 && crow.yv > 0
      crow.yv *= -1
    end
    chance_to_change_dir_y crow
  end

  def chance_to_change_dir_x crow
    # if crow is heading right and is to the right, a chance to go left
    if crow.x > 60 && crow.xv > 0
      if rand < 0.01
        crow.xv *= -1
        crow.flip = true
      end
    end
    # if crow is heading left and is to the left, a chance to go right
    if crow.x < 30 && crow.xv < 0
      if rand < 0.01
        crow.xv *= -1
        crow.flip = false
      end
    end
  end

  def chance_to_change_dir_y crow
    # crow is not too far up or down, there is a chance to switch directions
    if crow.y > 27 && crow.y < 49
      crow.yv *= -1 if rand < 0.01
    end
  end

  def deactivate_all_crows
    state.crows.each do |crow|
      set_state(entity: crow, state: :inactive)
    end
  end

  def set_state(entity: entity, state: state)
    case state
    when :move
      entity.state = :move
      entity.yv = 0
    when :spawn
      entity.state = :spawn
      entity.x = Numeric.rand(1..73)
      entity.y = 50 + Numeric.rand(30..40)
      entity.yv = -0.15
      entity.flip = false
      entity.offset = Numeric.rand(0..12)
      entity.flap_speed = [3, 4, 5].sample
    when :inactive
      entity.state = :inactive
    end
  end

  def set_defaults
    state.next_scene = :setup
    state.show_fps = false
    state.clock = 0
    state.score = 0
    state.high_score ||= 0
    state.total_score = 0
    state.score_multiplier = 1
    state.blink = false
    state.blink_time = 0
    state.blink_stop = 0
    state.wave = 1
    state.new_wave = true
    state.game_over = false
    state.game_over_at = nil
    state.game_paused = false
    state.active_crows = []
    state.bombs = []
    state.crow_rects = []
    state.hit_crows = []
    state.explosions = []
    state.cloud_x = 90
    state.cloud_y = 38
    state.raining = false
    state.cloud_hits = 0
    state.cloud_hit_time = nil
    state.cloud_rect = { x: 0, y: 0, w: 0, h: 0 }
    state.bomb_chance = 0.001
    state.extra_life = 10000
    state.frame_counter = 0
    state.wave_counter = 1
    state.shield_sprite_index = 0
    state.crows = Array.new(50) { |i| create_crow(id: i + 1) }
    deactivate_all_crows
    state.hat = {
      x: 0,
      y: 0,
      hat_stolen: false,
      hat_state: :worn,
      hat_rect: { x: 0, y: 0, w: 0, h: 0 }
    }
    state.player = {
      x: 28,
      y: 0,
      flip: false,
      anim: :idle,
      alive: true,
      lives: 3,
      shield: false,
      shield_at: 0,
      shield_visible: true,
      held: []
    }
    state.pitchforks = [
      { ox:  7, x: 7,  y: 0, w: 3, h: 6, held: false, respawn_timer: nil },
      { ox: 24, x: 24, y: 0, w: 3, h: 6, held: false, respawn_timer: nil },
      { ox: 41, x: 41, y: 0, w: 3, h: 6, held: false, respawn_timer: nil },
      { ox: 58, x: 58, y: 0, w: 3, h: 6, held: false, respawn_timer: nil },
      { ox: 75, x: 75, y: 0, w: 3, h: 6, held: false, respawn_timer: nil }
    ]
    state.cloud_pitchforks = [
      { ox:  7, x: 7,  y: -10, w: 3, h: 6 },
      { ox: 24, x: 24, y: -10, w: 3, h: 6 },
      { ox: 41, x: 41, y: -10, w: 3, h: 6 },
      { ox: 58, x: 58, y: -10, w: 3, h: 6 },
      { ox: 75, x: 75, y: -10, w: 3, h: 6 }
    ]

    # height information for each frame
    state.crow_frames = [
      { h: 10 }, # crow_0.png
      { h: 10 }, # crow_1.png
      { h: 10 }, # ...
      { h: 10 },
      { h: 10 },
      { h: 14 },
      { h: 13 },
      { h: 11 },
      { h: 10 },
      { h: 10 },
      { h: 10 },
      { h: 10 },
      { h: 10 },
    ]
  end

  def check_keys_change_mode
    # available modes are pause gameplay and show fps
    if inputs.keyboard.key_down.p && state.player.alive == true && state.player.shield == false
      state.game_paused = !state.game_paused
    end
    state.show_fps = !state.show_fps if inputs.keyboard.key_up.f
  end

  def render_bombs
    sprites_to_render = []
    state.bombs.each do |bomb|

      sprites_to_render << {
        x: bomb.x,
        y: bomb.y.to_i,
        w: 3,
        h: 3,
        path: "sprites/bomb.png"
      }
    end
    nokia.sprites << sprites_to_render
  end

  def render_explosions
    nokia.sprites << state.explosions
  end

  def render_player_lives
    x = 77
    sprites_to_render = []
    (state.player.lives - 1).each do |p|
      sprites_to_render << {
        x: x,
        y: 40,
        w: 7,
        h: 8,
        path: "sprites/mini.png"
      }
      x -= 6
    end
    nokia.sprites << sprites_to_render
  end

  def render_held_pitchfork_dots
    y = 1
    sprites_to_render = []
    state.pitchforks.each do |p|
      # only for pitchforks that are held
      next if !p[:held]
      sprites_to_render << {
        x: 1,
        y: y,
        w: 1,
        h: 1,
        path: :pixel,
        r: 0x43,
        g: 0x52,
        b: 0x3d
      }
      y += 2
    end
    nokia.sprites << sprites_to_render
  end

  def render_cloud
    pitchfork_rain
    state.cloud_rect = {
      x: state.cloud_x.to_i,
      y: state.cloud_y,
      w: 17,
      h: 10,
      path: "sprites/cloud_1.png"
    }
    sprites_to_render = []
    sprites_to_render << state.cloud_rect

    if state.cloud_hits > 0
      x = 2
      state.cloud_hits.each do |p|
        sprites_to_render << {
          x: state.cloud_x.to_i + x,
          y: state.cloud_y + 2,
          w: 1,
          h: 1,
          path: :pixel,
          r: 0x43,
          g: 0x52,
          b: 0x3d
        }
        x += 2
      end
    end

    nokia.sprites << sprites_to_render
  end

  def render_pitchforks
    sprites_to_render = []
    state.pitchforks.each do |p|
      # Render only pitchforks not held
      if !p[:held]
        sprites_to_render << {
          x: p[:x], y: p[:y], w: 3, h: 6,
          path: "sprites/pitchfork.png"
        }
      end
    end
    nokia.sprites << sprites_to_render
  end

  def render_crows
    sprites_to_render = []
    state.active_crows.each do |crow|

      if crow.hat == true
        sprites_to_render << {
          x: crow.x + (crow.flip == true ? -3 : 3),
          y: crow.y - 6,
          w: 10,
          h: 3,
          path: "sprites/hat.png"
        }
      end

      sprites_to_render << {
        x: crow.x,
        y: crow.y,
        w: 10,
        h: crow.h,
        path: "sprites/crow_#{crow.sprite_index}.png",
        flip_horizontally: crow[:flip],
        anchor_x: 0,
        anchor_y: 1
      }
    end
    nokia.sprites << sprites_to_render
  end

  def shield_rect
    { x:state.player.x - 4, y: state.player.y, w: 20, h: 16 }
  end

  def render_shield
    state.frame_counter += 1

    if state.frame_counter >= 40
      state.player.shield_visible = !state.player.shield_visible
      state.frame_counter = 0
      state.shield_sprite_index = 0
    end

    if state.player.shield_visible
      state.shield_sprite_index += 1
      if state.shield_sprite_index > 20
        state.shield_sprite_index = 0
      end
      sprite_index = 0.frame_index 2, 25, true, state.clock
      nokia.sprites << {
        x: state.player.x - 4,
        y: state.player.y - (sprite_index == 1 ? 1 : 0),
        w: 20,
        h: 18,
        path: "sprites/shield_#{state.shield_sprite_index < 10 ? 0 : 1}.png"
      }
    end
  end

  def render_player
    render_shield if state.player.shield == true
    # player blinks now and again
    if rand < 0.01 && !state.blink && (state.clock - state.blink_stop) > 180
      state.blink = true
      state.blink_time = state.clock
    end

    state.blink = false if state.game_paused == true

    if state.blink && (state.clock - state.blink_time) > 10
      state.blink = false
      state.blink_stop = state.clock  # Record when the last blink ended
    end

    if state.hat.hat_state == :worn
      state.hat.hat_rect = { x: state.player.x + 3, y: state.player.y + 10, w: 6, h: 4 }
    else
      state.hat.hat_rect = { x: state.hat.x + 2, y: (state.hat.y).to_i, w: 6, h: 4 }
    end

    if (state.player.anim == :idle || state.player.alive == false) && state.game_over == false
      # render the player's head
      sprite_index = 0.frame_index 2, 25, true, state.clock
      if state.player.alive == false
        sprite_index = 0
        state.player.y -= 0.2
        if state.player.y < -32
          state.player.alive = true
          if state.player.lives < 1
            state.game_over = true
            state.score_multiplier = 1
            state.extra_life = 10000
            state.player.alive = false
            state.next_scene = :over
            # explode all current crows, and send in a crazy bombing wave of them
            # state.bomb_chance = 0.01
          else
            state.player.shield_visible = true
            state.player.shield_at = state.clock
            state.player.shield = true
            state.player.y = 0
          end
        end
      end

      state.head_rect = { x: state.player.x + 1, y: 8 + state.player.y - (sprite_index == 1 ? 1 : 0), w: 10, h: 6 }
      render_hat sprite_index

      nokia.sprites << {
        x: state.player.x + 1,
        y: 8 + state.player.y - (sprite_index == 1 ? 1 : 0),
        w: 10,
        h: 6,
        path: state.blink ? "sprites/head_blink.png" : "sprites/head.png",
        flip_horizontally: state.player.flip
      }
      # render the player's idle body
      nokia.sprites << {
        x: state.player.x,
        y: state.player.y,
        w: 12,
        h: 8 - (sprite_index == 1 ? 1 : 0),
        path: "sprites/idle_#{sprite_index}.png"
      }

      elsif state.player.anim == :move && state.game_over == false && state.player.alive == true

        state.head_rect = { x: state.player.x + 1, y: 8 + state.player.y - (sprite_index == 1 ? 1 : 0), w: 10, h: 6 }
        render_hat sprite_index

        # render the player's head
        sprite_index = 0.frame_index 2, 15, true, state.clock
        nokia.sprites << {
          x: state.player.x + 1,
          y: 8 + state.player.y,
          w: 10,
          h: 6,
          path: state.blink ? "sprites/head_blink.png" : "sprites/head.png",
          flip_horizontally: state.player.flip
        }

        # render the player's move body
        nokia.sprites << {
          x: state.player.x,
          y: state.player.y,
          w: 12,
          h: 9,
          path: "sprites/move_#{sprite_index}.png"
        }
    end
  end

  def render_hat(sprite_index)
    unless state.hat.hat_stolen
      case state.hat.hat_state
      when :worn
        x = state.player.x + 1
        y = 11 + state.player.y - (sprite_index == 1 ? 1 : 0)
      when :fall
        if state.hat.y < 1
          state.hat.hat_state = :ground
          state.hat.y = 0
        end
        x = state.hat.x
        y = state.hat.y.to_i
        state.hat.y -=0.1 if state.hat.y >= 1 && !state.game_paused
        if geometry.intersect_rect?(state.hat.hat_rect, state.head_rect)
          state.hat.hat_state = :worn
          state.total_score += 1000
        end
      when :ground
        x = state.hat.x
        y = state.hat.y

        hl = x + 4
        hr = x + 5
        pl = state.player.x
        pr = state.player.x + 11

        if (hr - pl).abs < 6 || (hl - pl).abs < 6 || (hl - pr).abs < 6 || (hr - pr).abs < 6
          state.hat.hat_state = :worn
        end
      end
      nokia.sprites << {
        x: x,
        y: y,
        w: 10,
        h: 3,
        path: "sprites/hat.png"
      }
    end
  end

  def render_high_score
    # this doesn't belong here - crash into high score display
    state.crow_rects.each do |crow|
      if state.game_over == true
        high_score_rect = { x: 18, y: 16, w: 50, h: 15 }
        if geometry.intersect_rect?(high_score_rect, crow)
          state.hit_crows << { crow: crow }
        end
      end
    end

    nokia.labels << sm_label.merge(x: 20,
                                   y: 24,
                                   text: "High Score:",
                                   r: 0x43,
                                   g: 0x52,
                                   b: 0x3d)
    offset = ((47 - ((state.high_score.to_s.length * 5) -1)) / 2).to_i
    nokia.labels << sm_label.merge(x: 20 + offset,
                                   y: 18,
                                   text: "#{state.high_score}",
                                   r: 0x43,
                                   g: 0x52,
                                   b: 0x3d)
    nokia.borders << { x: 18, y: 16, w: 50, h: 15, r: 0x43, g: 0x52, b: 0x3d }
  end

  def render_score
    nokia.labels << sm_label.merge(x: 1,
                                   y: 42,
                                   text: "#{state.score}",
                                   r: 0x43,
                                   g: 0x52,
                                   b: 0x3d)
  end

  def render_fps
    return unless state.show_fps

    nokia.sprites << {
      x: 84 / 2, y: 48 / 2 - 1, w: 84, h: 19, path: :solid, r: 67, g: 82, b: 61,
      anchor_x: 0.5, anchor_y: 0.5
    }

    nokia.labels << sm_label.merge(x: 84 / 2,
                                   y: 48 / 2 + 6,
                                   r: 199, g: 240, b: 216,
                                   text: "Frame: #{GTK.current_framerate.round}",
                                   anchor_x: 0.5,
                                   anchor_y: 0.5)

    nokia.labels << sm_label.merge(x: 84 / 2,
                                   y: 48 / 2,
                                   r: 199, g: 240, b: 216,
                                   text: " Simul: #{GTK.current_framerate_calc.round}",
                                   anchor_x: 0.5,
                                   anchor_y: 0.5)

    nokia.labels << sm_label.merge(x: 84 / 2,
                                   y: 48 / 2 - 6,
                                   r: 199, g: 240, b: 216,
                                   text: "Rendr: #{GTK.current_framerate_render.round}",
                                   anchor_x: 0.5,
                                   anchor_y: 0.5)
  end

  def sm_label
    { x: 0, y: 0, size_px: 5, font: "fonts/cg-pixel-4-5.ttf", anchor_x: 0, anchor_y: 0 }
  end

  def md_label
    { x: 0, y: 0, size_px: 10, font: "fonts/cg-pixel-4-5.ttf", anchor_x: 0, anchor_y: 0 }
  end

  def lg_label
    { x: 0, y: 0, size_px: 15, font: "fonts/cg-pixel-4-5.ttf", anchor_x: 0, anchor_y: 0 }
  end

  def xl_label
    { x: 0, y: 0, size_px: 20, font: "fonts/cg-pixel-4-5.ttf", anchor_x: 0, anchor_y: 0 }
  end
end
